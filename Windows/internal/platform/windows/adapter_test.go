package windows

import (
	"context"
	"testing"
)

type mockExecutor struct {
	psOutput  string
	psErr     error
	cmdOutput string
	cmdErr    error
	runCmds   []string
	runPS     []string
}

func (m *mockExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	m.runCmds = append(m.runCmds, name+" "+args[0])
	return m.cmdOutput, m.cmdErr
}

func (m *mockExecutor) RunPowerShell(ctx context.Context, script string) (string, error) {
	m.runPS = append(m.runPS, script)
	return m.psOutput, m.psErr
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

func TestParseAdapterJSON(t *testing.T) {
	jsonSample := `[
		{
			"ID": "{2D46BA6A-1CED-4E84-9956-D2FD033CCEFA}",
			"Name": "WLAN",
			"Description": "Intel(R) Wi-Fi 6E AX210 160MHz",
			"Index": 8,
			"Status": "Up",
			"Gateway": "192.168.1.1",
			"IPv4DHCP": true,
			"IPv6DHCP": true,
			"IPv4DNS": ["192.168.1.1"],
			"IPv6DNS": ["fd12:ff09:4260::1"],
			"Virtual": false
		},
		{
			"ID": "{B476128E-D850-49DD-9F43-349A4523F800}",
			"Name": "以太网",
			"Description": "Realtek PCIe GbE Family Controller",
			"Index": 16,
			"Status": "Disconnected",
			"Gateway": "",
			"IPv4DHCP": true,
			"IPv6DHCP": true,
			"IPv4DNS": [],
			"IPv6DNS": null,
			"Virtual": false
		},
		{
			"ID": "{ADEF0804-6DCD-449A-9358-C0B5D2192AC4}",
			"Name": "vEthernet (Default Switch)",
			"Description": "Hyper-V Virtual Ethernet Adapter",
			"Index": 37,
			"Status": "Up",
			"Gateway": "",
			"IPv4DHCP": false,
			"IPv6DHCP": true,
			"IPv4DNS": null,
			"IPv6DNS": [],
			"Virtual": true
		}
	]`

	adapters, err := parseAdapterJSON(jsonSample)
	if err != nil {
		t.Fatalf("parseAdapterJSON failed: %v", err)
	}

	if len(adapters) != 3 {
		t.Fatalf("expected 3 adapters, got %d", len(adapters))
	}

	wlan := adapters[0]
	if !wlan.IsPhysical {
		t.Errorf("WLAN should be physical")
	}
	if len(wlan.IPv4DNS) != 1 || wlan.IPv4DNS[0] != "192.168.1.1" {
		t.Errorf("unexpected IPv4DNS for WLAN: %v", wlan.IPv4DNS)
	}

	eth := adapters[1]
	if !eth.IsPhysical {
		t.Errorf("以太网 should be physical")
	}
	if eth.Status != "Disconnected" {
		t.Errorf("unexpected status: %s", eth.Status)
	}

	vEth := adapters[2]
	if vEth.IsPhysical {
		t.Errorf("vEthernet should NOT be physical")
	}
}

func TestGetActivePhysicalAdapters_Mock(t *testing.T) {
	jsonSample := `[
		{
			"ID": "{GUID-1}",
			"Name": "WLAN",
			"Description": "Intel Wi-Fi",
			"Index": 8,
			"Status": "Up",
			"Gateway": "192.168.1.1",
			"IPv4DHCP": true,
			"IPv6DHCP": true,
			"IPv4DNS": "192.168.1.1",
			"IPv6DNS": [],
			"Virtual": false
		},
		{
			"ID": "{GUID-2}",
			"Name": "以太网",
			"Description": "Realtek Ethernet",
			"Index": 16,
			"Status": "Disconnected",
			"Gateway": "",
			"IPv4DHCP": true,
			"IPv6DHCP": true,
			"IPv4DNS": [],
			"IPv6DNS": [],
			"Virtual": false
		}
	]`

	mock := &mockExecutor{psOutput: jsonSample}
	scanner := NewAdapterScanner(mock)

	active, err := scanner.GetActivePhysicalAdapters(context.Background())
	if err != nil {
		t.Fatalf("GetActivePhysicalAdapters failed: %v", err)
	}

	if len(active) != 1 {
		t.Fatalf("expected 1 active physical adapter, got %d", len(active))
	}
	if active[0].Name != "WLAN" {
		t.Errorf("expected WLAN, got %s", active[0].Name)
	}
}

func TestPowerShellAdapterScanner_LiveScan(t *testing.T) {
	scanner := NewAdapterScanner(nil)
	adapters, err := scanner.ScanAll(context.Background())
	if err != nil {
		t.Logf("Live ScanAll skipped/failed (likely running in restricted environment): %v", err)
		return
	}
	t.Logf("Live ScanAll found %d adapters", len(adapters))
	for _, a := range adapters {
		t.Logf("Adapter: %s, Physical=%v, Status=%s, Gateway=%s", a.Name, a.IsPhysical, a.Status, a.Gateway)
	}
}

func TestParseAdapterJSON_WithErrorStreamPrefix(t *testing.T) {
	dirtyOutput := "Get-NetIPInterface : 找不到任何“InterfaceIndex”属性等于“45”的 MSFT_NetIPInterface 对象。\n" +
		"所在位置 行:1 字符: 10\n" +
		"[{\"ID\":\"{2D46BA6A-1CED-4E84-9956-D2FD033CCEFA}\",\"Name\":\"WLAN\",\"Description\":\"Intel Wi-Fi\",\"Index\":8,\"Status\":\"Up\",\"Gateway\":\"192.168.1.1\",\"IPv4DHCP\":true,\"IPv6DHCP\":true,\"IPv4DNS\":[\"192.168.1.1\"],\"IPv6DNS\":[],\"Virtual\":false}]\n"

	adapters, err := parseAdapterJSON(dirtyOutput)
	if err != nil {
		t.Fatalf("parseAdapterJSON should successfully parse JSON with error prefix, got err: %v", err)
	}
	if len(adapters) != 1 {
		t.Fatalf("expected 1 adapter, got %d", len(adapters))
	}
	if adapters[0].Name != "WLAN" {
		t.Errorf("expected WLAN, got %s", adapters[0].Name)
	}
}

func TestParseAdapterJSON_ComplexNoisyStreams(t *testing.T) {
	// 场景 1: 前缀包含 [警告] 括号与 {参数} 花括号，且带 UTF-8 BOM，尾部带 [INFO]
	noisyArray := "\xef\xbb\xbf[警告] 忽略无效网卡配置 [45] 附带元数据 {debug: true}\n" +
		"[{\"ID\":\"{TEST-1}\",\"Name\":\"Ethernet\",\"Description\":\"Realtek\",\"Index\":2,\"Status\":\"Up\",\"Gateway\":\"10.0.0.1\",\"IPv4DHCP\":true,\"IPv6DHCP\":false,\"IPv4DNS\":[\"10.0.0.1\"],\"IPv6DNS\":[],\"Virtual\":false}]\n" +
		"[INFO] 扫描完成\n"

	adapters, err := parseAdapterJSON(noisyArray)
	if err != nil {
		t.Fatalf("parseAdapterJSON failed on complex noisy array: %v", err)
	}
	if len(adapters) != 1 || adapters[0].Name != "Ethernet" {
		t.Fatalf("unexpected result from noisy array: %+v", adapters)
	}

	// 场景 2: 前缀带报错文本的单网卡对象输出 (非数组)
	noisySingle := "Error at {component}: adapter lookup failed\n" +
		"{\"ID\":\"{TEST-2}\",\"Name\":\"Wi-Fi\",\"Description\":\"Intel\",\"Index\":3,\"Status\":\"Up\",\"Gateway\":\"192.168.1.1\",\"IPv4DHCP\":true,\"IPv6DHCP\":true,\"IPv4DNS\":[\"1.1.1.1\"],\"IPv6DNS\":[],\"Virtual\":false}\n" +
		"Cleaning up...\n"

	singleAdapters, err := parseAdapterJSON(noisySingle)
	if err != nil {
		t.Fatalf("parseAdapterJSON failed on noisy single object: %v", err)
	}
	if len(singleAdapters) != 1 || singleAdapters[0].Name != "Wi-Fi" {
		t.Fatalf("unexpected result from noisy single object: %+v", singleAdapters)
	}
}


