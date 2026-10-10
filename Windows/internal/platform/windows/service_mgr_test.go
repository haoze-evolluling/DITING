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
	lastExe        string
	lastArgs       []string
	returnErr      error
	elevatedState  bool
}

func (m *mockPrivilegedExecutor) RunElevated(ctx context.Context, exe string, args ...string) error {
	m.elevatedCalled = true
	m.lastExe = exe
	m.lastArgs = args
	return m.returnErr
}

func (m *mockPrivilegedExecutor) IsElevated() bool {
	return m.elevatedState
}

type mockServiceCmdExecutor struct {
	cmdOutput string
	cmdErr    error
}

func (m *mockServiceCmdExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	return m.cmdOutput, m.cmdErr
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

func TestServiceManager_GetStatus_SCMError(t *testing.T) {
	ctx := context.Background()

	mgr := NewServiceManager(nil, nil)
	mgr.scmQuery = func(serviceName string) (bool, bool, string, error) {
		return false, false, "", errors.New("SCM disconnected")
	}

	_, err := mgr.GetStatus(ctx)
	if err == nil {
		t.Fatalf("expected error when SCM query fails, got nil")
	}
	if !strings.Contains(err.Error(), "检测核心服务状态失败") {
		t.Errorf("expected wrapped error, got: %v", err)
	}
}

func containsArg(args []string, target string) bool {
	for _, a := range args {
		if a == target {
			return true
		}
	}
	return false
}

func TestServiceManager_Actions(t *testing.T) {
	ctx := context.Background()
	mockExec := &mockServiceCmdExecutor{}
	mockPriv := &mockPrivilegedExecutor{elevatedState: false}
	mgr := NewServiceManager(mockExec, mockPriv)

	// 1. 测试 StartService
	err := mgr.StartService(ctx)
	if err != nil {
		t.Fatalf("StartService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !containsArg(mockPriv.lastArgs, "start") {
		t.Errorf("expected start action in elevated execution, got %v", mockPriv.lastArgs)
	}

	// 2. 测试 StopService
	mockPriv.elevatedCalled = false
	err = mgr.StopService(ctx)
	if err != nil {
		t.Fatalf("StopService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !containsArg(mockPriv.lastArgs, "stop") {
		t.Errorf("expected stop action in elevated execution, got %v", mockPriv.lastArgs)
	}

	// 3. 测试 RestartService
	mockPriv.elevatedCalled = false
	err = mgr.RestartService(ctx)
	if err != nil {
		t.Fatalf("RestartService error: %v", err)
	}
	if !mockPriv.elevatedCalled || len(mockPriv.lastArgs) == 0 {
		t.Errorf("expected elevated execution on restart")
	}

	// 4. 测试 InstallService
	mockPriv.elevatedCalled = false
	fakeExe := `C:\Diting\diting-service.exe`
	err = mgr.InstallService(ctx, fakeExe)
	if err != nil {
		t.Fatalf("InstallService error: %v", err)
	}
	if !mockPriv.elevatedCalled || !containsArg(mockPriv.lastArgs, "install") {
		t.Errorf("expected install in elevated execution, got %v", mockPriv.lastArgs)
	}

	// 5. 测试 InstallAndStartService
	mockPriv.elevatedCalled = false
	err = mgr.InstallAndStartService(ctx, fakeExe)
	if err != nil {
		t.Fatalf("InstallAndStartService error: %v", err)
	}
	if !mockPriv.elevatedCalled {
		t.Errorf("expected install and start in elevated execution")
	}

	// 6. 测试 UninstallService
	mockPriv.elevatedCalled = false
	err = mgr.UninstallService(ctx)
	if err != nil {
		t.Fatalf("UninstallService error: %v", err)
	}
	if !mockPriv.elevatedCalled {
		t.Errorf("expected elevated execution on uninstall")
	}
}

func TestServiceManager_UACCancelled(t *testing.T) {
	ctx := context.Background()
	mockPriv := &mockPrivilegedExecutor{
		returnErr: ErrUACCancelled,
	}
	mgr := NewServiceManager(nil, mockPriv)

	err := mgr.StartService(ctx)
	if !errors.Is(err, ErrUACCancelled) {
		t.Errorf("expected ErrUACCancelled, got: %v", err)
	}
}

func TestServiceManager_ElevatedExecutionError(t *testing.T) {
	ctx := context.Background()
	mockPriv := &mockPrivilegedExecutor{
		returnErr: errors.New("特权操作执行失败: code 1"),
	}
	mgr := NewServiceManager(nil, mockPriv)

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
	tmpDir := t.TempDir()
	fakeExe := filepath.Join(tmpDir, "diting-service.exe")
	if err := os.WriteFile(fakeExe, []byte("fake binary"), 0755); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	mgr := NewServiceManager(nil, nil)
	path, _ := mgr.LocateExecutable()
	if path != "" && !strings.HasSuffix(strings.ToLower(path), ".exe") {
		t.Errorf("expected path to end with .exe, got %s", path)
	}
}

func TestDefaultPrivilegedExecutor_CancelledContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // 预先取消

	exec := NewDefaultPrivilegedExecutor(nil)
	err := exec.RunElevated(ctx, "cmd.exe", "/c", "echo test")
	if !errors.Is(err, context.Canceled) {
		t.Errorf("expected context.Canceled, got: %v", err)
	}
}
