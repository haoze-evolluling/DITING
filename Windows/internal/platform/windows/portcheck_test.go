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
