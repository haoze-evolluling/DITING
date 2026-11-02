//go:build windows

package windows

import (
	"context"
	"strings"
	"testing"
)

type mockExecutor struct {
	cmdOutput string
	cmdErr    error
	runCmds   []string
}

func (m *mockExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	m.runCmds = append(m.runCmds, name+" "+strings.Join(args, " "))
	return m.cmdOutput, m.cmdErr
}

func TestNativeAdapterScanner_LiveScan(t *testing.T) {
	scanner := NewAdapterScanner(nil)
	adapters, err := scanner.ScanAll(context.Background())
	if err != nil {
		t.Logf("Live ScanAll skipped/failed: %v", err)
		return
	}
	t.Logf("Live ScanAll found %d adapters", len(adapters))
	for _, a := range adapters {
		t.Logf("Adapter: %s, Physical=%v, Status=%s, Gateway=%s", a.Name, a.IsPhysical, a.Status, a.Gateway)
	}

	active, err := scanner.GetActivePhysicalAdapters(context.Background())
	if err != nil {
		t.Fatalf("GetActivePhysicalAdapters failed: %v", err)
	}
	t.Logf("Active physical adapters: %d", len(active))
}
