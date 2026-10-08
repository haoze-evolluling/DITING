package windows

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type mockPrivilegedExecutor struct {
	elevatedCalled bool
	lastScript     string
	returnOutput   string
	returnErr      error
	elevatedState  bool
}

func (m *mockPrivilegedExecutor) RunElevated(ctx context.Context, script string) (string, error) {
	m.elevatedCalled = true
	m.lastScript = script
	return m.returnOutput, m.returnErr
}

func (m *mockPrivilegedExecutor) RunDirect(ctx context.Context, script string) (string, error) {
	m.lastScript = script
	return m.returnOutput, m.returnErr
}

func (m *mockPrivilegedExecutor) IsElevated() bool {
	return m.elevatedState
}

type mockServiceCmdExecutor struct {
	lastPowerShell string
	returnPSOutput string
	returnPSErr    error
}

func (m *mockServiceCmdExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	return "", nil
}

func (m *mockServiceCmdExecutor) RunPowerShell(ctx context.Context, script string) (string, error) {
	m.lastPowerShell = script
	return m.returnPSOutput, m.returnPSErr
}

func TestEncodePowerShell(t *testing.T) {
	raw := `Write-Output "Test"`
	encoded := encodePowerShell(raw)
	if encoded == "" {
		t.Fatalf("expected non-empty base64 string")
	}
}

func TestServiceManager_GetStatus_SCM(t *testing.T) {
	ctx := context.Background()

	mockPriv := &mockPrivilegedExecutor{elevatedState: false}
	mgr := NewServiceManager(nil, mockPriv)

	// 1. SCM 报告 未安装
	mgr.scmQuery = func(serviceName string) (bool, bool, string, error) {
		return false, false, "not_installed", nil
	}
	status, err := mgr.GetStatus(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status.Installed || status.State != "not_installed" {
		t.Errorf("expected not_installed, got %+v", status)
	}

	// 2. SCM 报告 运行中
	mgr.scmQuery = func(serviceName string) (bool, bool, string, error) {
		return true, true, "running", nil
	}
	status, err = mgr.GetStatus(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !status.Installed || !status.Running || status.State != "running" {
		t.Errorf("expected running, got %+v", status)
	}

	// 3. SCM 报告 已停止
	mgr.scmQuery = func(serviceName string) (bool, bool, string, error) {
		return true, false, "stopped", nil
	}
	status, err = mgr.GetStatus(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !status.Installed || status.Running || status.State != "stopped" {
		t.Errorf("expected stopped, got %+v", status)
	}
}

func TestServiceManager_GetStatus_PowerShellFallback(t *testing.T) {
	ctx := context.Background()

	mockExec := &mockServiceCmdExecutor{returnPSOutput: "NOT_INSTALLED"}
	mockPriv := &mockPrivilegedExecutor{elevatedState: false}
	mgr := NewServiceManager(mockExec, mockPriv)
	// 模拟 SCM 无法连接，强制走 PowerShell 降级通路
	mgr.scmQuery = func(serviceName string) (bool, bool, string, error) {
		return false, false, "", errors.New("SCM disconnected")
	}

	// 1. 测试未安装场景
	status, err := mgr.GetStatus(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status.Installed {
		t.Errorf("expected Installed to be false")
	}
	if status.State != "not_installed" {
		t.Errorf("expected state not_installed, got %s", status.State)
	}

	// 2. 测试已安装且运行场景
	mockExec.returnPSOutput = "Running"
	status, err = mgr.GetStatus(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !status.Installed || !status.Running {
		t.Errorf("expected Installed=true, Running=true")
	}
	if status.State != "running" {
		t.Errorf("expected state running, got %s", status.State)
	}

	// 3. 测试已安装且停止场景
	mockExec.returnPSOutput = "Stopped"
	status, err = mgr.GetStatus(ctx)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !status.Installed || status.Running {
		t.Errorf("expected Installed=true, Running=false")
	}
	if status.State != "stopped" {
		t.Errorf("expected state stopped, got %s", status.State)
	}
}

func TestServiceManager_Actions(t *testing.T) {
	ctx := context.Background()
	mockExec := &mockServiceCmdExecutor{}
	mockPriv := &mockPrivilegedExecutor{}
	mgr := NewServiceManager(mockExec, mockPriv)

	// 1. 测试 StartService
	err := mgr.StartService(ctx)
	if err != nil {
		t.Fatalf("StartService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !strings.Contains(mockPriv.lastScript, "Start-Service") {
		t.Errorf("expected Start-Service script in elevated execution")
	}

	// 2. 测试 StopService
	mockPriv.elevatedCalled = false
	err = mgr.StopService(ctx)
	if err != nil {
		t.Fatalf("StopService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !strings.Contains(mockPriv.lastScript, "Stop-Service") {
		t.Errorf("expected Stop-Service script in elevated execution")
	}

	// 3. 测试 RestartService
	mockPriv.elevatedCalled = false
	err = mgr.RestartService(ctx)
	if err != nil {
		t.Fatalf("RestartService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !strings.Contains(mockPriv.lastScript, "Restart-Service") {
		t.Errorf("expected Restart-Service script in elevated execution")
	}

	// 4. 测试 InstallService
	mockPriv.elevatedCalled = false
	fakeExe := `C:\Diting\diting-service.exe`
	err = mgr.InstallService(ctx, fakeExe)
	if err != nil {
		t.Fatalf("InstallService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !strings.Contains(mockPriv.lastScript, "-service install") {
		t.Errorf("expected -service install in elevated execution")
	}

	// 5. 测试 InstallAndStartService
	mockPriv.elevatedCalled = false
	err = mgr.InstallAndStartService(ctx, fakeExe)
	if err != nil {
		t.Fatalf("InstallAndStartService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !strings.Contains(mockPriv.lastScript, "Start-Service") || !strings.Contains(mockPriv.lastScript, "-service install") {
		t.Errorf("expected install and start in single elevated script")
	}

	// 6. 测试 UninstallService
	mockPriv.elevatedCalled = false
	err = mgr.UninstallService(ctx)
	if err != nil {
		t.Fatalf("UninstallService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !strings.Contains(mockPriv.lastScript, "sc.exe delete") {
		t.Errorf("expected sc.exe delete in elevated script")
	}
}

func TestServiceManager_UACCancelled(t *testing.T) {
	ctx := context.Background()
	mockExec := &mockServiceCmdExecutor{
		returnPSErr: errors.New("command failed: 1223 The operation was canceled by the user"),
	}
	privExec := NewDefaultPrivilegedExecutor(mockExec)
	mgr := NewServiceManager(mockExec, privExec)

	err := mgr.StartService(ctx)
	if !errors.Is(err, ErrUACCancelled) {
		t.Errorf("expected ErrUACCancelled, got: %v", err)
	}
}

func TestServiceManager_ElevatedExecutionError(t *testing.T) {
	ctx := context.Background()
	mockExec := &mockServiceCmdExecutor{
		returnPSErr: errors.New("command failed: service failed to start with code 1"),
	}
	privExec := NewDefaultPrivilegedExecutor(mockExec)
	mgr := NewServiceManager(mockExec, privExec)

	err := mgr.StartService(ctx)
	if err == nil {
		t.Fatalf("expected error, got nil")
	}
	if errors.Is(err, ErrUACCancelled) {
		t.Errorf("unexpected ErrUACCancelled for generic execution failure")
	}
	if !strings.Contains(err.Error(), "特权操作执行失败") {
		t.Errorf("expected wrapped error, got: %v", err)
	}
}

func TestServiceManager_LocateExecutable(t *testing.T) {
	// 创建临时可执行文件模拟
	tmpDir := t.TempDir()
	fakeExe := filepath.Join(tmpDir, "diting-service.exe")
	if err := os.WriteFile(fakeExe, []byte("fake binary"), 0755); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	mgr := NewServiceManager(nil, nil)
	// 测试真实环境下的可执行路径定位（不抛 panic）
	path, _ := mgr.LocateExecutable()
	// 如果本地有安装或开发构建产物，验证其包含 .exe
	if path != "" && !strings.HasSuffix(strings.ToLower(path), ".exe") {
		t.Errorf("expected path to end with .exe, got %s", path)
	}
}
