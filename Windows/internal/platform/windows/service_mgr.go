package windows

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"unicode/utf16"

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
)

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
	RunElevated(ctx context.Context, script string) (string, error)
	RunDirect(ctx context.Context, script string) (string, error)
	IsElevated() bool
}

// DefaultPrivilegedExecutor 默认特权命令执行器
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

func encodePowerShell(script string) string {
	runes := utf16.Encode([]rune(script))
	raw := make([]byte, len(runes)*2)
	for i, v := range runes {
		binary.LittleEndian.PutUint16(raw[i*2:], v)
	}
	return base64.StdEncoding.EncodeToString(raw)
}

// RunDirect 直接执行脚本
func (e *DefaultPrivilegedExecutor) RunDirect(ctx context.Context, script string) (string, error) {
	return e.executor.RunPowerShell(ctx, script)
}

// RunElevated 请求管理员权限执行脚本（通过 UAC 弹窗按需授权）
func (e *DefaultPrivilegedExecutor) RunElevated(ctx context.Context, script string) (string, error) {
	if e.IsElevated() {
		// 已具备管理员特权，直接执行无需二次弹窗
		return e.executor.RunPowerShell(ctx, script)
	}

	encoded := encodePowerShell(script)
	wrappedScript := fmt.Sprintf(`
try {
    $p = Start-Process powershell.exe -ArgumentList "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-EncodedCommand","%s" -Verb RunAs -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) {
        exit $p.ExitCode
    }
} catch {
    $msg = $_.Exception.Message
    [Console]::Error.WriteLine($msg)
    if ($_.Exception -is [System.ComponentModel.Win32Exception] -and $_.Exception.NativeErrorCode -eq 1223) {
        exit 1223
    }
    if ($msg -match "canceled|cancelled|取消") {
        exit 1223
    }
    exit 1
}
`, encoded)

	out, err := e.executor.RunPowerShell(ctx, wrappedScript)
	if err != nil {
		errStr := err.Error()
		if strings.Contains(errStr, "1223") ||
			strings.Contains(errStr, "canceled by the user") ||
			strings.Contains(errStr, "用户取消") ||
			strings.Contains(errStr, "canceled") {
			return "", ErrUACCancelled
		}
		return out, fmt.Errorf("特权操作执行失败: %w", err)
	}
	return out, nil
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

// GetStatus 获取当前核心服务状态
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

	// 优先使用 Windows SCM API 查询（超低延迟且标准用户免管理员权限）
	queryFn := m.scmQuery
	if queryFn == nil {
		queryFn = defaultSCMQuery
	}

	installed, running, state, err := queryFn(m.serviceName)
	if err == nil {
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

	// 备选降级方案：使用 PowerShell 查询
	psQuery := fmt.Sprintf(`$s = Get-Service -Name "%s" -ErrorAction SilentlyContinue; if ($null -eq $s) { "NOT_INSTALLED" } else { $s.Status.ToString() }`, m.serviceName)
	out, psErr := m.executor.RunPowerShell(ctx, psQuery)
	if psErr == nil {
		out = strings.TrimSpace(out)
		if out == "NOT_INSTALLED" || out == "" {
			status.Installed = false
			status.Running = false
			status.State = "not_installed"
			status.StateText = "未安装"
			status.Message = "后台核心服务尚未安装到系统中。"
		} else if strings.EqualFold(out, "Running") {
			status.Installed = true
			status.Running = true
			status.State = "running"
			status.StateText = "运行中"
			status.Message = "核心服务正常运行中。"
		} else {
			status.Installed = true
			status.Running = false
			status.State = "stopped"
			status.StateText = "已停止"
			status.Message = "核心服务已安装，当前处于停止状态。"
		}
		return status, nil
	}

	return status, fmt.Errorf("检测核心服务状态失败: %w", psErr)
}

// StartService 按需提权启动核心服务
func (m *ServiceManager) StartService(ctx context.Context) error {
	script := fmt.Sprintf(`
$s = Get-Service -Name "%s" -ErrorAction SilentlyContinue
if ($null -eq $s) {
    throw "服务未安装，无法启动"
}
if ($s.Status -ne 'Running') {
    Start-Service -Name "%s" -ErrorAction Stop
}
`, m.serviceName, m.serviceName)

	_, err := m.privExec.RunElevated(ctx, script)
	return err
}

// StopService 按需提权停止核心服务
func (m *ServiceManager) StopService(ctx context.Context) error {
	script := fmt.Sprintf(`
$s = Get-Service -Name "%s" -ErrorAction SilentlyContinue
if ($null -ne $s -and $s.Status -eq 'Running') {
    Stop-Service -Name "%s" -Force -ErrorAction Stop
}
`, m.serviceName, m.serviceName)

	_, err := m.privExec.RunElevated(ctx, script)
	return err
}

// RestartService 按需提权重启核心服务
func (m *ServiceManager) RestartService(ctx context.Context) error {
	script := fmt.Sprintf(`
$s = Get-Service -Name "%s" -ErrorAction SilentlyContinue
if ($null -eq $s) {
    throw "服务未安装，无法重启"
}
Restart-Service -Name "%s" -Force -ErrorAction Stop
`, m.serviceName, m.serviceName)

	_, err := m.privExec.RunElevated(ctx, script)
	return err
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

	script := fmt.Sprintf(`
$s = Get-Service -Name "%s" -ErrorAction SilentlyContinue
if ($null -eq $s) {
    & "%s" -service install
    if ($LASTEXITCODE -ne 0) {
        throw "注册服务失败 (代码: $LASTEXITCODE)"
    }
}
sc.exe config %s start= auto
`, m.serviceName, exePath, m.serviceName)

	_, err := m.privExec.RunElevated(ctx, script)
	return err
}

// InstallAndStartService 按需提权一键安装并立即启动核心服务（单次 UAC 授权）
func (m *ServiceManager) InstallAndStartService(ctx context.Context, exePath string) error {
	if exePath == "" {
		p, err := m.LocateExecutable()
		if err != nil {
			return err
		}
		exePath = p
	}

	script := fmt.Sprintf(`
$s = Get-Service -Name "%s" -ErrorAction SilentlyContinue
if ($null -eq $s) {
    & "%s" -service install
    if ($LASTEXITCODE -ne 0) {
        throw "注册服务失败 (代码: $LASTEXITCODE)"
    }
    sc.exe config %s start= auto
    $s = Get-Service -Name "%s" -ErrorAction SilentlyContinue
}
if ($null -ne $s -and $s.Status -ne 'Running') {
    Start-Service -Name "%s" -ErrorAction Stop
}
`, m.serviceName, exePath, m.serviceName, m.serviceName, m.serviceName)

	_, err := m.privExec.RunElevated(ctx, script)
	return err
}

// UninstallService 按需提权卸载核心服务
func (m *ServiceManager) UninstallService(ctx context.Context) error {
	exePath, _ := m.LocateExecutable()
	var script string
	if exePath != "" {
		script = fmt.Sprintf(`
Stop-Service -Name "%s" -Force -ErrorAction SilentlyContinue
& "%s" -service uninstall
sc.exe delete %s
`, m.serviceName, exePath, m.serviceName)
	} else {
		script = fmt.Sprintf(`
Stop-Service -Name "%s" -Force -ErrorAction SilentlyContinue
sc.exe delete %s
`, m.serviceName, m.serviceName)
	}

	_, err := m.privExec.RunElevated(ctx, script)
	return err
}
