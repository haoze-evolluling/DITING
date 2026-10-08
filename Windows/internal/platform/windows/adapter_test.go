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

func TestIsVirtualAdapter(t *testing.T) {
	tests := []struct {
		name        string
		desc        string
		virtualFlag bool
		wantVirtual bool
	}{
		{"singbox_tun", "sing-tun Tunnel", true, true},
		{"WLAN", "Intel(R) Wi-Fi 6E AX210 160MHz", false, false},
		{"以太网", "Realtek PCIe GbE Family Controller", false, false},
		{"vEthernet (WSL)", "Hyper-V Virtual Ethernet Adapter", true, true},
		{"Tailscale", "Tailscale Tunnel", false, true},
		{"Loopback Pseudo-Interface 1", "Software Loopback Interface 1", false, true},
		{"OpenVPN TAP", "TAP-Windows Adapter V9", false, true},
		{"VMware Network", "VMware Virtual Ethernet Adapter", false, true},
	}

	for _, tt := range tests {
		got := IsVirtualAdapter(tt.name, tt.desc, tt.virtualFlag)
		if got != tt.wantVirtual {
			t.Errorf("IsVirtualAdapter(%s, %s, %v) = %v; want %v", tt.name, tt.desc, tt.virtualFlag, got, tt.wantVirtual)
		}
	}
}

func TestHasValidIPv4Gateway(t *testing.T) {
	tests := []struct {
		gw   string
		want bool
	}{
		{"", false},
		{"0.0.0.0", false},
		{"127.0.0.1", false},
		{"::1", false},
		{"invalid", false},
		{"192.168.1.1", true},
		{"10.0.0.1", true},
		{"172.16.0.1", true},
	}

	for _, tt := range tests {
		got := HasValidIPv4Gateway(tt.gw)
		if got != tt.want {
			t.Errorf("HasValidIPv4Gateway(%s) = %v; want %v", tt.gw, got, tt.want)
		}
	}
}

func TestFilterLoopbackIPs(t *testing.T) {
	input := []string{
		"127.0.0.1",
		"::1",
		"[::1]",
		"[::1]:53",
		"[127.0.0.1]:53",
		"0.0.0.0",
		"::",
		"127.0.0.53",
		"127.1.2.3:53",
		"localhost",
		"8.8.8.8",
		"1.1.1.1",
		"2001:4860:4860::8888",
		"",
	}
	got := FilterLoopbackIPs(input)
	want := []string{"8.8.8.8", "1.1.1.1", "2001:4860:4860::8888"}

	if len(got) != len(want) {
		t.Fatalf("FilterLoopbackIPs returned %d items, want %d: %v", len(got), len(want), got)
	}
	for i, v := range want {
		if got[i] != v {
			t.Errorf("FilterLoopbackIPs[%d] = %s; want %s", i, got[i], v)
		}
	}
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
