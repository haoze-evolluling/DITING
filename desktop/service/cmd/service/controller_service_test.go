package main

import (
	"context"
	"errors"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// stubServiceManager 以固定结果模拟平台服务管理器。
type stubServiceManager struct {
	status *platform.CoreServiceStatus
	err    error
}

func (s *stubServiceManager) GetStatus(ctx context.Context) (*platform.CoreServiceStatus, error) {
	return s.status, s.err
}
func (s *stubServiceManager) StartService(ctx context.Context) error             { return nil }
func (s *stubServiceManager) StopService(ctx context.Context) error              { return nil }
func (s *stubServiceManager) RestartService(ctx context.Context) error           { return nil }
func (s *stubServiceManager) InstallService(ctx context.Context, _ string) error { return nil }
func (s *stubServiceManager) InstallAndStartService(ctx context.Context, _ string) error {
	return nil
}
func (s *stubServiceManager) UninstallService(ctx context.Context) error { return nil }
func (s *stubServiceManager) LocateExecutable() (string, error)          { return "", nil }

// TestGetCoreServiceStatus_ForegroundMode 验证未注册系统服务但服务进程
// 正在响应时，状态被如实描述为前台运行，而非误导性的"未安装"。
func TestGetCoreServiceStatus_ForegroundMode(t *testing.T) {
	prg := &program{
		dnsRunning: true,
		serviceMgr: &stubServiceManager{
			status: &platform.CoreServiceStatus{
				Installed: false,
				Running:   false,
				State:     "not_installed",
				StateText: "未安装",
			},
		},
	}

	status, err := prg.GetCoreServiceStatus(context.Background())
	if err != nil {
		t.Fatalf("GetCoreServiceStatus error: %v", err)
	}
	if !status.Running {
		t.Errorf("期望前台运行时报告 Running=true, got %+v", status)
	}
	if status.State != "foreground" {
		t.Errorf("期望 state=foreground, got %q", status.State)
	}
	if status.StateText != "前台运行中" {
		t.Errorf("期望 stateText=前台运行中, got %q", status.StateText)
	}
	if status.Message == "" {
		t.Error("期望非空的状态说明")
	}
	if status.ExecutablePath == "" {
		t.Error("期望以前台进程自身路径兜底填充核心程序位置")
	}
	if !status.CanInstall {
		t.Error("已定位到可执行文件时 CanInstall 应为 true")
	}
}

// TestGetCoreServiceStatus_InstalledUnchanged 验证已注册为系统服务时，
// 不覆写平台层给出的真实状态。
func TestGetCoreServiceStatus_InstalledUnchanged(t *testing.T) {
	prg := &program{
		dnsRunning: true,
		serviceMgr: &stubServiceManager{
			status: &platform.CoreServiceStatus{
				Installed: true,
				Running:   true,
				State:     "running",
				StateText: "运行中",
				Message:   "核心服务正常运行中。",
			},
		},
	}

	status, err := prg.GetCoreServiceStatus(context.Background())
	if err != nil {
		t.Fatalf("GetCoreServiceStatus error: %v", err)
	}
	if status.State != "running" || status.StateText != "运行中" {
		t.Errorf("已安装服务的状态不应被覆写, got %+v", status)
	}
}

// TestGetCoreServiceStatus_PartialStatusOnError 验证查询出错但仍返回部分状态时，
// 保留状态并补充错误原因，而不是整体失败导致前端退化为占位文案。
func TestGetCoreServiceStatus_PartialStatusOnError(t *testing.T) {
	prg := &program{
		serviceMgr: &stubServiceManager{
			status: &platform.CoreServiceStatus{
				Installed:      true,
				ExecutablePath: `C:\DITING\diting-service.exe`,
			},
			err: errors.New("SCM 查询超时"),
		},
	}

	status, err := prg.GetCoreServiceStatus(context.Background())
	if err != nil {
		t.Fatalf("部分状态可用时不应返回错误: %v", err)
	}
	if status.Message != "SCM 查询超时" {
		t.Errorf("期望补充错误原因, got %q", status.Message)
	}
	if status.ExecutablePath == "" {
		t.Error("期望保留已获取的可执行路径")
	}
}

// TestGetCoreServiceStatus_NilManager 验证服务管理器未初始化时明确报错。
func TestGetCoreServiceStatus_NilManager(t *testing.T) {
	prg := &program{}
	if _, err := prg.GetCoreServiceStatus(context.Background()); err == nil {
		t.Fatal("期望在服务管理器缺失时返回错误")
	}
}
