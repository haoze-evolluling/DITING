package ipc

import (
	"context"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

func TestServer_AutofixPortConflicts(t *testing.T) {
	mockCtrl := &mockController{
		portResult: &windows.PortCheckResult{
			Available:  false,
			HasICS:     true,
			CanAutofix: true,
			Conflicts: []windows.PortConflict{
				{
					Port:         53,
					Protocol:     "UDP",
					LocalAddress: "0.0.0.0:53",
					PID:          1768,
					ProcessName:  "svchost.exe",
					ServiceName:  "SharedAccess",
					IsICS:        true,
				},
			},
			Diagnostic: "检测到 Windows ICS 服务正在运行",
		},
	}

	token := "autofix-secret-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() {
		_ = server.Shutdown(context.Background())
	}()

	client := NewClient(server.Addr(), token)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// 1. 先验证 CheckPortConflicts 能获取到初始状态
	checkRes, err := client.CheckPortConflicts(ctx)
	if err != nil {
		t.Fatalf("CheckPortConflicts failed: %v", err)
	}
	if checkRes.Available || !checkRes.HasICS || !checkRes.CanAutofix {
		t.Fatalf("expected HasICS=true, CanAutofix=true, Available=false, got %+v", checkRes)
	}

	// 2. 调用 AutofixPortConflicts 并拉起 DNS
	fixRes, err := client.AutofixPortConflicts(ctx, true)
	if err != nil {
		t.Fatalf("AutofixPortConflicts failed: %v", err)
	}
	if !fixRes.Available {
		t.Fatalf("expected Available=true after autofix, got %+v", fixRes)
	}

	// 3. 验证 DNS 状态已成功拉起
	status, err := client.GetStatus(ctx)
	if err != nil {
		t.Fatalf("GetStatus failed: %v", err)
	}
	if !status.DNS.Running {
		t.Fatalf("expected DNS to be running after autofix with startDNS=true")
	}
}
