//go:build linux

package linux

import (
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

func TestParseResolvConf(t *testing.T) {
	content := "# comment\n; another\nnameserver 192.168.1.1\nnameserver 2001:db8::1\nsearch example.com\noptions timeout:2\n"
	got := parseResolvConf(content)
	want := []string{"192.168.1.1", "2001:db8::1"}
	if len(got) != len(want) {
		t.Fatalf("服务器数量不符: got=%v want=%v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("第 %d 项不符: got=%q want=%q", i, got[i], want[i])
		}
	}
}

func TestParseResolvConfEmpty(t *testing.T) {
	if got := parseResolvConf(""); len(got) != 0 {
		t.Fatalf("空内容应无服务器, got=%v", got)
	}
}

func TestRenderResolvConfRoundTrip(t *testing.T) {
	rendered := renderResolvConf([]string{"127.0.0.1", "::1"})
	if got := parseResolvConf(rendered); len(got) != 2 || got[0] != "127.0.0.1" || got[1] != "::1" {
		t.Fatalf("渲染后解析回读不一致: %v", got)
	}
}

func TestParseResolvectlDNS(t *testing.T) {
	out := "Global:\nLink 2 (eth0): 192.168.1.1 2001:db8::1\nLink 3 (wlan0):\nLink 4 (docker0): 172.17.0.1\n"
	got := parseResolvectlDNS(out)

	if servers := got["eth0"]; len(servers) != 2 || servers[0] != "192.168.1.1" || servers[1] != "2001:db8::1" {
		t.Errorf("eth0 解析不符: %v", servers)
	}
	if _, ok := got["wlan0"]; ok {
		t.Errorf("无服务器的链路不应登记, got=%v", got["wlan0"])
	}
	if servers := got["docker0"]; len(servers) != 1 || servers[0] != "172.17.0.1" {
		t.Errorf("docker0 解析不符: %v", servers)
	}
}

func TestParseSystemctlShow(t *testing.T) {
	out := "LoadState=loaded\nActiveState=active\nSubState=running\n"
	st := parseSystemctlShow(out)
	if st.loadState != "loaded" || st.activeState != "active" || st.subState != "running" {
		t.Fatalf("systemctl show 解析不符: %+v", st)
	}
}

func TestApplyServiceStatus(t *testing.T) {
	cases := []struct {
		name          string
		st            serviceStatus
		wantInstalled bool
		wantRunning   bool
		wantState     string
	}{
		{"未安装", serviceStatus{loadState: "not-found"}, false, false, "not_installed"},
		{"运行中", serviceStatus{loadState: "loaded", activeState: "active"}, true, true, "running"},
		{"已停止", serviceStatus{loadState: "loaded", activeState: "inactive"}, true, false, "stopped"},
		{"失败", serviceStatus{loadState: "loaded", activeState: "failed"}, true, false, "stopped"},
		{"启动中", serviceStatus{loadState: "loaded", activeState: "activating"}, true, false, "start_pending"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			status := &platform.CoreServiceStatus{}
			applyServiceStatus(status, c.st)
			if status.Installed != c.wantInstalled || status.Running != c.wantRunning || status.State != c.wantState {
				t.Fatalf("状态映射不符: got installed=%v running=%v state=%q",
					status.Installed, status.Running, status.State)
			}
		})
	}
}

func TestParseExecStartPath(t *testing.T) {
	cases := map[string]string{
		"{ path=/usr/local/bin/diting-service ; argv[]=/usr/local/bin/diting-service -run ; ignore_errors=no }": "/usr/local/bin/diting-service",
		"/opt/diting/diting-service -run": "/opt/diting/diting-service",
		"":                                "",
		"unknown":                         "",
	}
	for in, want := range cases {
		if got := parseExecStartPath(in); got != want {
			t.Errorf("parseExecStartPath(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestDnsBackendKindString(t *testing.T) {
	cases := map[dnsBackendKind]string{
		backendNone:            "none",
		backendSystemdResolved: "systemd-resolved",
		backendNetworkManager:  "NetworkManager",
		backendResolvConf:      "resolv.conf",
	}
	for kind, want := range cases {
		if got := kind.String(); got != want {
			t.Errorf("dnsBackendKind(%d).String() = %q, want %q", kind, got, want)
		}
	}
}

func TestUfwRulePresent(t *testing.T) {
	out := "Status: active\n\nTo                         Action      From\n--                         ------      ----\n53/udp                     ALLOW       Anywhere\n15353/tcp                  ALLOW       Anywhere\n"
	if !ufwRulePresent(out, 53, "udp") {
		t.Errorf("应识别到 53/udp 放行规则")
	}
	if !ufwRulePresent(out, 15353, "tcp") {
		t.Errorf("应识别到 15353/tcp 放行规则")
	}
	if ufwRulePresent(out, 53, "tcp") {
		t.Errorf("不应误报 53/tcp 放行规则")
	}
}

func TestIptablesBinary(t *testing.T) {
	if got := iptablesBinary("udp"); got != "iptables" {
		t.Errorf("udp 应使用 iptables, got=%q", got)
	}
	if got := iptablesBinary("tcp6"); got != "ip6tables" {
		t.Errorf("tcp6 应使用 ip6tables, got=%q", got)
	}
}

func TestParseSystemctlShowUnitFileState(t *testing.T) {
	out := "LoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\n"
	st := parseSystemctlShow(out)
	if st.unitFileState != "enabled" {
		t.Fatalf("UnitFileState 解析不符: %+v", st)
	}
}

// TestAutoStartStatusSystemd 验证 systemd 已 enable 时如实报告自启生效，
// 避免 Web 控制台误报"未配置开机启动"。
func TestAutoStartStatusSystemd(t *testing.T) {
	mgr := NewServiceManager(nil, nil)

	cases := []struct {
		name        string
		unitState   string
		wantEnabled bool
		wantMech    string
	}{
		{"已启用", "enabled", true, platform.AutoStartMechanismSystemd},
		{"已禁用", "disabled", false, platform.AutoStartMechanismNone},
		{"已屏蔽", "masked", false, platform.AutoStartMechanismNone},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := mgr.autoStartStatus(serviceStatus{unitFileState: c.unitState})
			if got.Enabled != c.wantEnabled {
				t.Errorf("Enabled 不符: got %v, want %v", got.Enabled, c.wantEnabled)
			}
			if got.Mechanism != c.wantMech {
				t.Errorf("Mechanism 不符: got %q, want %q", got.Mechanism, c.wantMech)
			}
			if got.Detail == "" {
				t.Error("Detail 不应为空")
			}
		})
	}
}

// TestAutoStartStatusXDGFallback 验证无 systemd 托管信息时回退检查 XDG 桌面条目。
func TestAutoStartStatusXDGFallback(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", home+"/.config")

	mgr := NewServiceManager(nil, nil)

	// 1. 无桌面条目 → 未配置
	if got := mgr.autoStartStatus(serviceStatus{}); got.Enabled {
		t.Errorf("无任何自启配置时不应报告已启用: %+v", got)
	}

	// 2. 存在桌面条目 → 判定为已配置开机自启
	if _, err := NewAutoStartManager().SetEnabled(true); err != nil {
		t.Fatalf("SetEnabled 失败: %v", err)
	}

	got := mgr.autoStartStatus(serviceStatus{})
	if !got.Enabled {
		t.Errorf("存在 XDG 桌面条目时应报告已启用: %+v", got)
	}
	if got.Mechanism != platform.AutoStartMechanismXDG {
		t.Errorf("Mechanism 不符: got %q, want %q", got.Mechanism, platform.AutoStartMechanismXDG)
	}
}
