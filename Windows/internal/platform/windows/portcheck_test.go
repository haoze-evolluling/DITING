package windows

import (
	"context"
	"strings"
	"testing"
)

func TestFormatPortConflicts_WithICS(t *testing.T) {
	listeners := []nativePortListener{
		{
			Protocol:     "UDP",
			LocalAddress: "0.0.0.0:53",
			PID:          1824,
			ProcessName:  "svchost.exe",
		},
	}

	conflicts, hasICS, diag := formatPortConflicts(listeners, true, 1824, true, 0)
	if !hasICS {
		t.Fatalf("expected hasICS = true")
	}
	if len(conflicts) != 1 {
		t.Fatalf("expected 1 conflict, got %d", len(conflicts))
	}
	if !conflicts[0].IsICS {
		t.Errorf("expected conflict to be flagged as ICS")
	}
	if !strings.Contains(diag, "SharedAccess") || !strings.Contains(diag, "Internet Connection Sharing") {
		t.Errorf("diagnostic message should mention SharedAccess/ICS: %s", diag)
	}
}

func TestFormatPortConflicts_OtherProcess(t *testing.T) {
	listeners := []nativePortListener{
		{
			Protocol:     "UDP",
			LocalAddress: "127.0.0.1:53",
			PID:          9999,
			ProcessName:  "acrylic.exe",
		},
	}

	conflicts, hasICS, diag := formatPortConflicts(listeners, false, 0, false, 0)
	if hasICS {
		t.Fatalf("expected hasICS = false")
	}
	if len(conflicts) != 1 {
		t.Fatalf("expected 1 conflict")
	}
	if conflicts[0].IsICS {
		t.Errorf("should not be ICS")
	}
	if !strings.Contains(diag, "acrylic.exe") {
		t.Errorf("expected acrylic.exe in diagnosis: %s", diag)
	}
}

func TestFormatPortConflicts_Clean(t *testing.T) {
	listeners := []nativePortListener{}

	conflicts, hasICS, diag := formatPortConflicts(listeners, false, 0, true, 0)
	if hasICS || len(conflicts) != 0 {
		t.Fatalf("expected clean result, got hasICS=%v, conflicts=%d", hasICS, len(conflicts))
	}
	if !strings.Contains(diag, "空闲且可用") {
		t.Errorf("expected clean diagnosis, got %s", diag)
	}
}

func TestFormatPortConflicts_SelfProcess(t *testing.T) {
	listeners := []nativePortListener{
		{
			Protocol:     "UDP",
			LocalAddress: "127.0.0.1:53",
			PID:          1234,
			ProcessName:  "diting-service.exe",
		},
	}

	conflicts, hasICS, diag := formatPortConflicts(listeners, false, 0, false, 1234)
	if hasICS {
		t.Fatalf("expected hasICS = false")
	}
	if len(conflicts) != 1 {
		t.Fatalf("expected 1 conflict entry")
	}
	if !conflicts[0].IsSelf {
		t.Errorf("expected conflict to be flagged as IsSelf")
	}
	if !strings.Contains(diag, "谛听 (DITING) 核心服务监听中") {
		t.Errorf("expected diagnosis to acknowledge DITING self service: %s", diag)
	}
}

func TestWindowsPortChecker_LiveCheck(t *testing.T) {
	checker := NewPortChecker(nil)
	res, err := checker.CheckPort53(context.Background())
	if err != nil {
		t.Fatalf("CheckPort53 failed: %v", err)
	}

	t.Logf("Port 53 check result: Available=%v, HasICS=%v, Conflicts=%d", res.Available, res.HasICS, len(res.Conflicts))
	t.Logf("Diagnostic: %s", res.Diagnostic)
}

func TestWindowsPortChecker_RealSocketCheck(t *testing.T) {
	checker := NewPortChecker(nil)
	resLoopback, err := checker.CheckPort53ForAddresses(context.Background(), []string{"127.0.0.1:53"}, []string{"127.0.0.1:53"})
	if err != nil {
		t.Fatalf("CheckPort53ForAddresses loopback failed: %v", err)
	}
	t.Logf("Loopback check: available=%v, hasICS=%v, canAutofix=%v", resLoopback.Available, resLoopback.HasICS, resLoopback.CanAutofix)

	resLAN, err := checker.CheckPort53ForAddresses(context.Background(), []string{"0.0.0.0:53"}, []string{"0.0.0.0:53"})
	if err != nil {
		t.Fatalf("CheckPort53ForAddresses LAN failed: %v", err)
	}
	t.Logf("LAN check: available=%v, hasICS=%v, canAutofix=%v", resLAN.Available, resLAN.HasICS, resLAN.CanAutofix)
	if resLAN.HasICS && !resLAN.Available {
		if !resLAN.CanAutofix {
			t.Errorf("expected CanAutofix=true when LAN port 53 is blocked by ICS")
		}
	}
}

func TestEvaluatePortAvailability(t *testing.T) {
	icsConflict := PortConflict{
		Port:         53,
		Protocol:     "UDP",
		LocalAddress: "0.0.0.0:53",
		PID:          1768,
		ProcessName:  "svchost.exe",
		ServiceName:  "SharedAccess",
		IsICS:        true,
	}
	thirdPartyConflict := PortConflict{
		Port:         53,
		Protocol:     "UDP",
		LocalAddress: "0.0.0.0:53",
		PID:          9999,
		ProcessName:  "named.exe",
		IsICS:        false,
	}
	selfConflict := PortConflict{
		Port:         53,
		Protocol:     "UDP",
		LocalAddress: "127.0.0.1:53",
		PID:          1234,
		ProcessName:  "diting-service.exe",
		IsSelf:       true,
	}

	lanAddrs := []string{"0.0.0.0:53"}
	loopbackAddrs := []string{"127.0.0.1:53"}

	// 1. 套接字绑定成功（无冲突）
	res := evaluatePortAvailability(true, nil, false, "ok", loopbackAddrs, loopbackAddrs)
	if !res.Available || res.CanAutofix {
		t.Errorf("expected Available=true, CanAutofix=false for free sockets, got %+v", res)
	}

	// 2. 套接字绑定成功，但系统后台有 ICS（仅监听回环模式不应被 ICS 误杀）
	res = evaluatePortAvailability(true, []PortConflict{icsConflict}, true, "ics running", loopbackAddrs, loopbackAddrs)
	if !res.Available || res.CanAutofix {
		t.Errorf("expected Available=true, CanAutofix=false when loopback bound successfully despite ICS, got %+v", res)
	}

	// 3. 局域网模式 (0.0.0.0:53) 绑定失败，且仅被 ICS 占用 -> 必须可自动修复
	res = evaluatePortAvailability(false, []PortConflict{icsConflict}, true, "ics block", lanAddrs, lanAddrs)
	if res.Available || !res.CanAutofix {
		t.Errorf("expected Available=false, CanAutofix=true when LAN blocked only by ICS, got %+v", res)
	}
	if !strings.Contains(res.Diagnostic, "一键自动修复并启动") {
		t.Errorf("expected autofix guidance in diagnostic: %s", res.Diagnostic)
	}

	// 4. 局域网模式绑定失败，ICS 与第三方进程同时占用 -> 不可一键自动修复（必须人工关闭第三方程序）
	res = evaluatePortAvailability(false, []PortConflict{icsConflict, thirdPartyConflict}, true, "dual block", lanAddrs, lanAddrs)
	if res.Available || res.CanAutofix {
		t.Errorf("expected Available=false, CanAutofix=false when blocked by both ICS and 3rd party, got %+v", res)
	}
	if !strings.Contains(res.Diagnostic, "第三方外部程序") {
		t.Errorf("expected third party mention in diagnostic: %s", res.Diagnostic)
	}

	// 5. 仅第三方占用 -> 不可自动修复
	res = evaluatePortAvailability(false, []PortConflict{thirdPartyConflict}, false, "3rd block", loopbackAddrs, loopbackAddrs)
	if res.Available || res.CanAutofix {
		t.Errorf("expected Available=false, CanAutofix=false for 3rd party conflict, got %+v", res)
	}

	// 6. 谛听自身 PID 正在监听 -> Available = true
	res = evaluatePortAvailability(false, []PortConflict{selfConflict}, false, "self listening", loopbackAddrs, loopbackAddrs)
	if !res.Available || res.CanAutofix {
		t.Errorf("expected Available=true for self listener, got %+v", res)
	}
}
