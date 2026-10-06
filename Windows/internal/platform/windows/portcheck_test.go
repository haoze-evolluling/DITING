package windows

import (
	"context"
	"strings"
	"testing"
)

func TestParsePortCheckJSON_WithICS(t *testing.T) {
	jsonSample := `{
		"Listeners": [
			{
				"Protocol": "UDP",
				"LocalAddress": "0.0.0.0:53",
				"PID": 1824,
				"ProcessName": "svchost"
			}
		],
		"ICS": {
			"Name": "SharedAccess",
			"ProcessId": 1824,
			"State": "Running"
		}
	}`

	conflicts, hasICS, diag := parsePortCheckJSON(jsonSample, true)
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

func TestParsePortCheckJSON_OtherProcess(t *testing.T) {
	jsonSample := `{
		"Listeners": [
			{
				"Protocol": "UDP",
				"LocalAddress": "127.0.0.1:53",
				"PID": 9999,
				"ProcessName": "acrylic.exe"
			}
		],
		"ICS": null
	}`

	conflicts, hasICS, diag := parsePortCheckJSON(jsonSample, false)
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

func TestParsePortCheckJSON_Clean(t *testing.T) {
	jsonSample := `{
		"Listeners": [],
		"ICS": null
	}`

	conflicts, hasICS, diag := parsePortCheckJSON(jsonSample, true)
	if hasICS || len(conflicts) != 0 {
		t.Fatalf("expected clean result, got hasICS=%v, conflicts=%d", hasICS, len(conflicts))
	}
	if !strings.Contains(diag, "空闲且可用") {
		t.Errorf("expected clean diagnosis, got %s", diag)
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
