package windows

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const (
	// DefaultServiceName 谛听后台核心服务名称
	DefaultServiceName = "DitingDNSService"
	// DefaultServiceDisplayName 谛听后台核心服务显示名称
	DefaultServiceDisplayName = "谛听 DNS 内核特权服务"
)

var (
	// ErrUACCancelled 用户取消管理员权限授权
	ErrUACCancelled = errors.New("用户取消了管理员权限授权")
	// ErrServiceExeNotFound 未找到核心服务执行程序
	ErrServiceExeNotFound = errors.New("未找到后台核心服务执行程序 (diting-service.exe)")

	modShell32          = windows.NewLazySystemDLL("shell32.dll")
	procShellExecuteExW = modShell32.NewProc("ShellExecuteExW")
)

const (
	seeMaskNoCloseProcess = 0x00000040
	swHide                = 0
)

type shellExecuteInfo struct {
	cbSize       uint32
	fMask        uint32
	hwnd         windows.Handle
	lpVerb       *uint16
	lpFile       *uint16
	lpParameters *uint16
	lpDirectory  *uint16
	nShow        int32
	hInstApp     windows.Handle
	lpIDList     uintptr
	lpClass      *uint16
	hkeyClass    windows.Handle
	dwHotKey     uint32
	hIcon        windows.Handle
	hProcess     windows.Handle
}

// CoreServiceStatus 核心服务状态
type CoreServiceStatus struct {
	Installed      bool   `json:"installed"`
	Running        bool   `json:"running"`
	State          string `json:"state"` // running, stopped, not_installed, start_pending, stop_pending, unknown
	StateText      string `json:"stateText"`
	ExecutablePath string `json:"executablePath"`
	IsElevated     bool   `json:"isElevated"`
	CanInstall     bool   `json:"canInstall"`
	Message        string `json:"message"`
}

// PrivilegedExecutor 特权命令执行接口，支持测试 Mock
type PrivilegedExecutor interface {
	RunElevated(ctx context.Context, exe string, args ...string) error
	IsElevated() bool
}

// DefaultPrivilegedExecutor 默认特权命令执行器（基于 Win32 原生 API）
type DefaultPrivilegedExecutor struct {
	executor CommandExecutor
}

// NewDefaultPrivilegedExecutor 创建默认特权执行器
func NewDefaultPrivilegedExecutor(executor CommandExecutor) *DefaultPrivilegedExecutor {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	return &DefaultPrivilegedExecutor{executor: executor}
}

// IsRunningAsAdmin 检查当前进程是否具有管理员令牌
func IsRunningAsAdmin() bool {
	var sid *windows.SID
	err := windows.AllocateAndInitializeSid(
		&windows.SECURITY_NT_AUTHORITY,
		2,
		windows.SECURITY_BUILTIN_DOMAIN_RID,
		windows.DOMAIN_ALIAS_RID_ADMINS,
		0, 0, 0, 0, 0, 0,
		&sid,
	)
	if err != nil {
		return false
	}
	defer windows.FreeSid(sid)

	token := windows.GetCurrentProcessToken()
	member, err := token.IsMember(sid)
	if err != nil {
		return false
	}
	return member
}

func (e *DefaultPrivilegedExecutor) IsElevated() bool {
	return IsRunningAsAdmin()
}

func runElevatedNative(exePath string, args string) error {
	verbPtr, _ := windows.UTF16PtrFromString("runas")
	filePtr, _ := windows.UTF16PtrFromString(exePath)
	var argsPtr *uint16
	if args != "" {
		argsPtr, _ = windows.UTF16PtrFromString(args)
	}

	var sei shellExecuteInfo
	sei.cbSize = uint32(unsafe.Sizeof(sei))
	sei.fMask = seeMaskNoCloseProcess
	sei.lpVerb = verbPtr
	sei.lpFile = filePtr
	sei.lpParameters = argsPtr
	sei.nShow = swHide

	r1, _, err := procShellExecuteExW.Call(uintptr(unsafe.Pointer(&sei)))
	if r1 == 0 {
		if errors.Is(err, windows.ERROR_CANCELLED) || strings.Contains(err.Error(), "1223") {
			return ErrUACCancelled
		}
		return fmt.Errorf("特权操作执行失败: %w", err)
	}

	if sei.hProcess != 0 {
		defer windows.CloseHandle(sei.hProcess)
		event, errWait := windows.WaitForSingleObject(sei.hProcess, windows.INFINITE)
		if errWait != nil || event != windows.WAIT_OBJECT_0 {
			return fmt.Errorf("等待提权进程退出失败: %w", errWait)
		}

		var exitCode uint32
		if errExit := windows.GetExitCodeProcess(sei.hProcess, &exitCode); errExit == nil && exitCode != 0 {
			return fmt.Errorf("特权操作执行失败 (退出代码: %d)", exitCode)
		}
	}
	return nil
}

// RunElevated 请求管理员权限执行程序（底层使用 Win32 ShellExecuteEx 原生 API）
func (e *DefaultPrivilegedExecutor) RunElevated(ctx context.Context, exe string, args ...string) error {
	if e.IsElevated() {
		cmd := exec.CommandContext(ctx, exe, args...)
		out, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("特权操作执行失败: %w (输出: %s)", err, strings.TrimSpace(string(out)))
		}
		return nil
	}
	return runElevatedNative(exe, strings.Join(args, " "))
}

type scmQuerier func(serviceName string) (installed bool, running bool, state string, err error)

func defaultSCMQuery(serviceName string) (bool, bool, string, error) {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return false, false, "", err
	}
	defer windows.CloseServiceHandle(scm)

	namePtr, _ := windows.UTF16PtrFromString(serviceName)
	svc, err := windows.OpenService(scm, namePtr, windows.SERVICE_QUERY_STATUS)
	if err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
			return false, false, "not_installed", nil
		}
		return false, false, "", err
	}
	defer windows.CloseServiceHandle(svc)

	var svcStatus windows.SERVICE_STATUS
	if err := windows.QueryServiceStatus(svc, &svcStatus); err != nil {
		return false, false, "", err
	}

	switch svcStatus.CurrentState {
	case windows.SERVICE_RUNNING:
		return true, true, "running", nil
	case windows.SERVICE_STOPPED:
		return true, false, "stopped", nil
	case windows.SERVICE_START_PENDING:
		return true, false, "start_pending", nil
	case windows.SERVICE_STOP_PENDING:
		return true, false, "stop_pending", nil
	default:
		return true, false, "stopped", nil
	}
}

// ServiceManager 管理 Windows 后台服务生命周期
type ServiceManager struct {
	serviceName string
	executor    CommandExecutor
	privExec    PrivilegedExecutor
	scmQuery    scmQuerier
}

// NewServiceManager 创建服务管理器
func NewServiceManager(executor CommandExecutor, privExec PrivilegedExecutor) *ServiceManager {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	if privExec == nil {
		privExec = NewDefaultPrivilegedExecutor(executor)
	}
	return &ServiceManager{
		serviceName: DefaultServiceName,
		executor:    executor,
		privExec:    privExec,
		scmQuery:    defaultSCMQuery,
	}
}

// LocateExecutable 寻找 diting-service.exe 可执行文件位置
func (m *ServiceManager) LocateExecutable() (string, error) {
	// 1. 尝试从注册表已注册的服务 ImagePath 获取
	if k, err := registry.OpenKey(registry.LOCAL_MACHINE, `SYSTEM\CurrentControlSet\Services\`+m.serviceName, registry.QUERY_VALUE); err == nil {
		defer k.Close()
		if imgPath, _, err := k.GetStringValue("ImagePath"); err == nil {
			clean := strings.TrimSpace(imgPath)
			clean = os.ExpandEnv(clean)
			clean = strings.Trim(clean, "\"")
			if idx := strings.Index(strings.ToLower(clean), ".exe"); idx != -1 {
				clean = clean[:idx+4]
			}
			clean = strings.Trim(clean, "\"")
			if _, err := os.Stat(clean); err == nil {
				return clean, nil
			}
		}
	}

	// 2. 检查 GUI 所在同级目录
	if exePath, err := os.Executable(); err == nil {
		dir := filepath.Dir(exePath)
		target := filepath.Join(dir, "diting-service.exe")
		if _, err := os.Stat(target); err == nil {
			return target, nil
		}
		// 检查构建目录与源码开发目录
		candidates := []string{
			filepath.Join(dir, "build", "bin", "diting-service.exe"),
			filepath.Join(dir, "..", "build", "bin", "diting-service.exe"),
			filepath.Join(dir, "..", "..", "build", "bin", "diting-service.exe"),
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				abs, _ := filepath.Abs(c)
				return abs, nil
			}
		}
	}

	// 2.1 检查当前工作目录（适配开发调试环境）
	if cwd, err := os.Getwd(); err == nil {
		cwdCandidates := []string{
			filepath.Join(cwd, "diting-service.exe"),
			filepath.Join(cwd, "build", "bin", "diting-service.exe"),
			filepath.Join(cwd, "..", "build", "bin", "diting-service.exe"),
			filepath.Join(cwd, "Windows", "build", "bin", "diting-service.exe"),
		}
		for _, c := range cwdCandidates {
			if _, err := os.Stat(c); err == nil {
				abs, _ := filepath.Abs(c)
				return abs, nil
			}
		}
	}

	// 3. 检查标准系统安装目录
	progFiles := os.Getenv("ProgramFiles")
	if progFiles != "" {
		target := filepath.Join(progFiles, "Diting", "谛听 DNS", "diting-service.exe")
		if _, err := os.Stat(target); err == nil {
			return target, nil
		}
	}
	progFilesX86 := os.Getenv("ProgramFiles(x86)")
	if progFilesX86 != "" {
		target := filepath.Join(progFilesX86, "Diting", "谛听 DNS", "diting-service.exe")
		if _, err := os.Stat(target); err == nil {
			return target, nil
		}
	}
	localApp := os.Getenv("LOCALAPPDATA")
	if localApp != "" {
		target := filepath.Join(localApp, "Programs", "谛听 DNS", "diting-service.exe")
		if _, err := os.Stat(target); err == nil {
			return target, nil
		}
	}

	// 4. 检查系统 PATH
	if p, err := exec.LookPath("diting-service.exe"); err == nil {
		abs, _ := filepath.Abs(p)
		return abs, nil
	}

	return "", ErrServiceExeNotFound
}

// GetStatus 获取当前核心服务状态（纯 Windows 原生 SCM API）
func (m *ServiceManager) GetStatus(ctx context.Context) (*CoreServiceStatus, error) {
	status := &CoreServiceStatus{
		State:      "unknown",
		StateText:  "未知状态",
		IsElevated: m.privExec.IsElevated(),
	}

	exePath, err := m.LocateExecutable()
	if err == nil {
		status.ExecutablePath = exePath
		status.CanInstall = true
	} else {
		status.CanInstall = false
	}

	queryFn := m.scmQuery
	if queryFn == nil {
		queryFn = defaultSCMQuery
	}

	installed, running, state, err := queryFn(m.serviceName)
	if err != nil {
		return status, fmt.Errorf("检测核心服务状态失败: %w", err)
	}

	status.Installed = installed
	status.Running = running
	status.State = state
	switch state {
	case "running":
		status.StateText = "运行中"
		status.Message = "核心服务正常运行中。"
	case "stopped":
		status.StateText = "已停止"
		status.Message = "核心服务已安装，当前处于停止状态。"
	case "start_pending":
		status.StateText = "正在启动"
		status.Message = "核心服务正在启动中..."
	case "stop_pending":
		status.StateText = "正在停止"
		status.Message = "核心服务正在停止中..."
	case "not_installed":
		status.StateText = "未安装"
		status.Message = "后台核心服务尚未安装到系统中。"
	default:
		status.StateText = "已停止"
		status.Message = "核心服务未运行。"
	}
	return status, nil
}

func startServiceNative(serviceName string) error {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return fmt.Errorf("打开服务控制管理器失败: %w", err)
	}
	defer windows.CloseServiceHandle(scm)

	namePtr, _ := windows.UTF16PtrFromString(serviceName)
	svc, err := windows.OpenService(scm, namePtr, windows.SERVICE_START)
	if err != nil {
		return fmt.Errorf("打开服务 [%s] 失败: %w", serviceName, err)
	}
	defer windows.CloseServiceHandle(svc)

	if err := windows.StartService(svc, 0, nil); err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_ALREADY_RUNNING) {
			return nil
		}
		return fmt.Errorf("启动服务 [%s] 失败: %w", serviceName, err)
	}
	return nil
}

func stopServiceNative(serviceName string) error {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return fmt.Errorf("打开服务控制管理器失败: %w", err)
	}
	defer windows.CloseServiceHandle(scm)

	namePtr, _ := windows.UTF16PtrFromString(serviceName)
	svc, err := windows.OpenService(scm, namePtr, windows.SERVICE_STOP|windows.SERVICE_QUERY_STATUS)
	if err != nil {
		return fmt.Errorf("打开服务 [%s] 失败: %w", serviceName, err)
	}
	defer windows.CloseServiceHandle(svc)

	var status windows.SERVICE_STATUS
	if err := windows.ControlService(svc, windows.SERVICE_CONTROL_STOP, &status); err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_NOT_ACTIVE) {
			return nil
		}
		return fmt.Errorf("停止服务 [%s] 失败: %w", serviceName, err)
	}
	return nil
}

func deleteServiceNative(serviceName string) error {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return err
	}
	defer windows.CloseServiceHandle(scm)

	namePtr, _ := windows.UTF16PtrFromString(serviceName)
	svc, err := windows.OpenService(scm, namePtr, windows.DELETE)
	if err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
			return nil
		}
		return err
	}
	defer windows.CloseServiceHandle(svc)
	return windows.DeleteService(svc)
}

// StartService 按需提权启动核心服务
func (m *ServiceManager) StartService(ctx context.Context) error {
	if m.privExec.IsElevated() {
		if err := startServiceNative(m.serviceName); err == nil {
			return nil
		}
	}

	exePath, err := m.LocateExecutable()
	if err == nil {
		return m.privExec.RunElevated(ctx, exePath, "-service", "start")
	}
	return m.privExec.RunElevated(ctx, "sc.exe", "start", m.serviceName)
}

// StopService 按需提权停止核心服务
func (m *ServiceManager) StopService(ctx context.Context) error {
	if m.privExec.IsElevated() {
		if err := stopServiceNative(m.serviceName); err == nil {
			return nil
		}
	}

	exePath, err := m.LocateExecutable()
	if err == nil {
		return m.privExec.RunElevated(ctx, exePath, "-service", "stop")
	}
	return m.privExec.RunElevated(ctx, "sc.exe", "stop", m.serviceName)
}

// RestartService 按需提权重启核心服务
func (m *ServiceManager) RestartService(ctx context.Context) error {
	if m.privExec.IsElevated() {
		_ = stopServiceNative(m.serviceName)
		time.Sleep(300 * time.Millisecond)
		if err := startServiceNative(m.serviceName); err == nil {
			return nil
		}
	}

	exePath, err := m.LocateExecutable()
	if err == nil {
		return m.privExec.RunElevated(ctx, exePath, "-service", "restart")
	}
	_ = m.privExec.RunElevated(ctx, "sc.exe", "stop", m.serviceName)
	return m.privExec.RunElevated(ctx, "sc.exe", "start", m.serviceName)
}

// InstallService 按需提权安装核心服务
func (m *ServiceManager) InstallService(ctx context.Context, exePath string) error {
	if exePath == "" {
		p, err := m.LocateExecutable()
		if err != nil {
			return err
		}
		exePath = p
	}

	return m.privExec.RunElevated(ctx, exePath, "-service", "install")
}

// InstallAndStartService 按需提权一键安装并立即启动核心服务
func (m *ServiceManager) InstallAndStartService(ctx context.Context, exePath string) error {
	if exePath == "" {
		p, err := m.LocateExecutable()
		if err != nil {
			return err
		}
		exePath = p
	}

	if err := m.InstallService(ctx, exePath); err != nil {
		// 若已安装，继续尝试启动
	}
	return m.StartService(ctx)
}

// UninstallService 按需提权卸载核心服务
func (m *ServiceManager) UninstallService(ctx context.Context) error {
	if m.privExec.IsElevated() {
		_ = stopServiceNative(m.serviceName)
		exePath, err := m.LocateExecutable()
		if err == nil {
			_ = m.privExec.RunElevated(ctx, exePath, "-service", "uninstall")
		}
		return deleteServiceNative(m.serviceName)
	}

	exePath, err := m.LocateExecutable()
	if err == nil {
		return m.privExec.RunElevated(ctx, exePath, "-service", "uninstall")
	}
	return m.privExec.RunElevated(ctx, "sc.exe", "delete", m.serviceName)
}
