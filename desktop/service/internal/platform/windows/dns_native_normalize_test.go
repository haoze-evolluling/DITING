//go:build windows

package windows

import (
	"reflect"
	"testing"
)

// TestNormalizeDNSAddress 覆盖实测会被 Windows 拒绝、或需要归一化后才能下发的形态。
//
// 依据（Win11 实测 SetInterfaceDnsSettings 返回码）：
// v4 栈收到 IPv6 地址 / v6 栈收到 IPv4 地址 / `fe80::1%8` / `[fe80::1]` / `8.8.8.8:53` /
// URL 全部返回 87，且一条坏地址会让整次调用作废；`NameServer = NULL` 表示恢复 DHCP。
func TestNormalizeDNSAddress(t *testing.T) {
	cases := []struct {
		raw    string
		isIPv6 bool
		want   string
		ok     bool
	}{
		{"192.168.1.1", false, "192.168.1.1", true},
		{" 192.168.1.1 ", false, "192.168.1.1", true},
		{"192.168.1.1:53", false, "192.168.1.1", true},
		{"[fe80::1]", true, "fe80::1", true},
		{"[fe80::1]:53", true, "fe80::1", true},
		{"fe80::1%12", true, "fe80::1", true},
		{"2606:4700:4700::1111", true, "2606:4700:4700::1111", true},
		{"2408:844B:2030:FC4D::F9", true, "2408:844b:2030:fc4d::f9", true},
		// 族不匹配：必须被丢掉，否则整次调用 87
		{"fe80::1", false, "", false},
		{"192.168.1.1", true, "", false},
		{"::ffff:192.168.1.1", true, "", false},
		// 非 IP 字面量
		{"https://doh.pub/dns-query", false, "", false},
		{"dns.google", false, "", false},
		{"", false, "", false},
		{"   ", true, "", false},
	}
	for _, c := range cases {
		got, ok := normalizeDNSAddress(c.raw, c.isIPv6)
		if ok != c.ok || got != c.want {
			t.Errorf("normalizeDNSAddress(%q, isIPv6=%v) = (%q, %v), want (%q, %v)",
				c.raw, c.isIPv6, got, ok, c.want, c.ok)
		}
	}
}

func TestNormalizeServersForStack(t *testing.T) {
	cases := []struct {
		name        string
		in          []string
		isIPv6      bool
		wantKept    []string
		wantDropped []string
	}{
		{
			name:        "混合列表按栈拆分并丢弃异族地址",
			in:          []string{"8.8.8.8", "fe80::1%12", "1.1.1.1:53", "https://doh.pub/dns-query"},
			isIPv6:      false,
			wantKept:    []string{"8.8.8.8", "1.1.1.1"},
			wantDropped: []string{"fe80::1%12", "https://doh.pub/dns-query"},
		},
		{
			name:        "IPv6 栈只保留 IPv6（方括号会被剥除，回环过滤由上游 CleanAdapterState 负责）",
			in:          []string{"192.168.1.1", "2606:4700:4700::1111", "[::1]"},
			isIPv6:      true,
			wantKept:    []string{"2606:4700:4700::1111", "::1"},
			wantDropped: []string{"192.168.1.1"},
		},
		{
			name:        "重复地址去重",
			in:          []string{"8.8.8.8", "8.8.8.8", " 8.8.8.8 "},
			isIPv6:      false,
			wantKept:    []string{"8.8.8.8"},
			wantDropped: nil,
		},
		{
			name:        "全为非法地址时返回空列表（调用方会退回 DHCP）",
			in:          []string{"fe80::1%12"},
			isIPv6:      false,
			wantKept:    nil,
			wantDropped: []string{"fe80::1%12"},
		},
		{
			name:        "空列表",
			in:          nil,
			isIPv6:      true,
			wantKept:    nil,
			wantDropped: nil,
		},
	}
	for _, c := range cases {
		kept, dropped := normalizeServersForStack(c.in, c.isIPv6)
		if !reflect.DeepEqual(kept, c.wantKept) {
			t.Errorf("%s: kept = %v, want %v", c.name, kept, c.wantKept)
		}
		if !reflect.DeepEqual(dropped, c.wantDropped) {
			t.Errorf("%s: dropped = %v, want %v", c.name, dropped, c.wantDropped)
		}
	}
}
