//go:build windows

package windows

import (
	"context"
	"errors"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/platform"
	"golang.org/x/sys/windows"
)

// newAutoStartTestManager 构造一个隔离于真实系统的服务管理器。
//
// 通过注入 SCM 查询、启动类型与登录自启项，验证自启托管判定逻辑，
// 不依赖宿主机是否真的安装过谛听服务。
func newAutoStartTestManager(
	installed, running bool,
	startType uint32,
	startTypeErr error,
	loginItem bool,
) *ServiceManager {
	mgr := NewServiceManager(nil, &mockPrivilegedExecutor{})
	mgr.locateExe = func() (string, error) { return `C:\DITING\diting-service.exe`, nil }
	mgr.scmQuery = func(serviceName string) (bool, bool, string, error) {
		if !installed {
			return false, false, "not_installed", nil
		}
		if running {
			return true, true, "running", nil
		}
		return true, false, "stopped", nil
	}
	mgr.startTypeQuery = func(serviceName string) (uint32, error) {
		return startType, startTypeErr
	}
	mgr.loginItemCheck = func() bool { return loginItem }
	return mgr
}

// TestAutoStartStatus_ServiceAutoStart 验证 SCM 服务设为自动启动时，
// 界面不应再显示"未配置开机启动"——这正是 Web 控制台的误报根因。
func TestAutoStartStatus_ServiceAutoStart(t *testing.T) {
	mgr := newAutoStartTestManager(true, true, windows.SERVICE_AUTO_START, nil, false)

	status, err := mgr.GetStatus(context.Background())
	if err != nil {
		t.Fatalf("GetStatus error: %v", err)
	}
	if status.AutoStart == nil {
		t.Fatal("expected autostart status, got nil")
	}
	if !status.AutoStart.Enabled {
		t.Errorf("expected enabled autostart, got %+v", status.AutoStart)
	}
	if status.AutoStart.Mechanism != platform.AutoStartMechanismService {
		t.Errorf("expected mechanism %q, got %q",
			platform.AutoStartMechanismService, status.AutoStart.Mechanism)
	}
	if status.AutoStart.Detail == "" {
		t.Error("expected non-empty autostart detail")
	}
}

// TestAutoStartStatus_LoginItemFallback 验证服务为手动启动、但存在
// 用户登录自启项时，仍应判定为已配置开机自启。
func TestAutoStartStatus_LoginItemFallback(t *testing.T) {
	mgr := newAutoStartTestManager(true, false, windows.SERVICE_DEMAND_START, nil, true)

	status, err := mgr.GetStatus(context.Background())
	if err != nil {
		t.Fatalf("GetStatus error: %v", err)
	}
	if status.AutoStart == nil || !status.AutoStart.Enabled {
		t.Fatalf("expected enabled autostart from login item, got %+v", status.AutoStart)
	}
	if status.AutoStart.Mechanism != platform.AutoStartMechanismLoginItem {
		t.Errorf("expected mechanism %q, got %q",
			platform.AutoStartMechanismLoginItem, status.AutoStart.Mechanism)
	}
}

// TestAutoStartStatus_DisabledService 验证服务被显式禁用时如实报告未自启，
// 即使存在登录自启项（禁用服务不会随开机运行）。
func TestAutoStartStatus_DisabledService(t *testing.T) {
	mgr := newAutoStartTestManager(true, false, windows.SERVICE_DISABLED, nil, true)

	status, err := mgr.GetStatus(context.Background())
	if err != nil {
		t.Fatalf("GetStatus error: %v", err)
	}
	if status.AutoStart == nil {
		t.Fatal("expected autostart status, got nil")
	}
	if status.AutoStart.Enabled {
		t.Errorf("expected disabled autostart, got %+v", status.AutoStart)
	}
}

// TestAutoStartStatus_NotInstalledNoLoginItem 验证未安装且无自启项时
// 返回明确的"未配置"状态，而非空值导致的占位文案。
func TestAutoStartStatus_NotInstalledNoLoginItem(t *testing.T) {
	mgr := newAutoStartTestManager(false, false, 0, errors.New("service not found"), false)

	status, err := mgr.GetStatus(context.Background())
	if err != nil {
		t.Fatalf("GetStatus error: %v", err)
	}
	if status.AutoStart == nil {
		t.Fatal("expected autostart status, got nil")
	}
	if status.AutoStart.Enabled {
		t.Errorf("expected disabled autostart, got %+v", status.AutoStart)
	}
	if status.AutoStart.Mechanism != platform.AutoStartMechanismNone {
		t.Errorf("expected mechanism %q, got %q",
			platform.AutoStartMechanismNone, status.AutoStart.Mechanism)
	}
}

// TestAutoStartStatus_StartTypeQueryError 验证启动类型查询失败时不误判为已自启，
// 但可通过登录自启项兜底。
func TestAutoStartStatus_StartTypeQueryError(t *testing.T) {
	mgr := newAutoStartTestManager(true, true, 0, errors.New("access denied"), false)

	status, err := mgr.GetStatus(context.Background())
	if err != nil {
		t.Fatalf("GetStatus error: %v", err)
	}
	if status.AutoStart == nil {
		t.Fatal("expected autostart status, got nil")
	}
	if status.AutoStart.Enabled {
		t.Errorf("expected unknown/disabled autostart on query error, got %+v", status.AutoStart)
	}
}
