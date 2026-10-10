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

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

// ServiceManager 管理 Windows 后台服务生命周期
type ServiceManager struct {
	serviceName string
	executor    CommandExecutor
	privExec    PrivilegedExecutor
	scmQuery    scmQuerier
	locateExe   func() (string, error)
}

// NewServiceManager 创建服务管理器
func NewServiceManager(executor CommandExecutor, privExec PrivilegedExecutor) *ServiceManager {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	if privExec == nil {
		privExec = NewDefaultPrivilegedExecutor(executor)
	}
	m := &ServiceManager{
		serviceName: DefaultServiceName,
		executor:    executor,
		privExec:    privExec,
		scmQuery:    defaultSCMQuery,
	}
	m.locateExe = m.LocateExecutable
	return m
}

// locate 定位服务可执行文件（locateExe 便于测试注入）
func (m *ServiceManager) locate() (string, error) {
	if m.locateExe != nil {
		return m.locateExe()
	}
	return m.LocateExecutable()
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

	// 2. 检查 GUI 所在同级目录及构建产物目录
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

	// 3. 检查系统 PATH
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

	exePath, err := m.locate()
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

	exePath, err := m.locate()
	if err != nil {
		return err
	}
	return m.privExec.RunElevated(ctx, exePath, "-service", "start")
}

// StopService 按需提权停止核心服务
func (m *ServiceManager) StopService(ctx context.Context) error {
	if m.privExec.IsElevated() {
		if err := stopServiceNative(m.serviceName); err == nil {
			return nil
		}
	}

	exePath, err := m.locate()
	if err != nil {
		return err
	}
	return m.privExec.RunElevated(ctx, exePath, "-service", "stop")
}

// RestartService 按需提权重启核心服务
func (m *ServiceManager) RestartService(ctx context.Context) error {
	if m.privExec.IsElevated() {
		_ = stopServiceNative(m.serviceName)
		// 轮询等待服务停止（最多等待 3 秒）
		for i := 0; i < 30; i++ {
			time.Sleep(100 * time.Millisecond)
			_, running, _, _ := defaultSCMQuery(m.serviceName)
			if !running {
				break
			}
		}
		if err := startServiceNative(m.serviceName); err == nil {
			return nil
		}
	}

	exePath, err := m.locate()
	if err != nil {
		return err
	}
	return m.privExec.RunElevated(ctx, exePath, "-service", "restart")
}

// InstallService 按需提权安装核心服务
func (m *ServiceManager) InstallService(ctx context.Context, exePath string) error {
	if exePath == "" {
		p, err := m.locate()
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
		p, err := m.locate()
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
		exePath, err := m.locate()
		if err == nil {
			_ = m.privExec.RunElevated(ctx, exePath, "-service", "uninstall")
		}
		return deleteServiceNative(m.serviceName)
	}

	exePath, err := m.locate()
	if err != nil {
		return err
	}
	return m.privExec.RunElevated(ctx, exePath, "-service", "uninstall")
}
