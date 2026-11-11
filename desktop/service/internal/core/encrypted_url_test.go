package core

import (
	"reflect"
	"testing"
)

func TestDoHURLs(t *testing.T) {
	cases := []struct {
		name  string
		hosts []string
		port  int
		path  string
		want  []string
	}{
		{
			"默认端口不写进地址",
			[]string{"dns.lan"},
			443,
			"/dns-query",
			[]string{"https://dns.lan/dns-query"},
		},
		{
			"非默认端口必须显式写出",
			[]string{"dns.lan"},
			8443,
			"/dns-query",
			[]string{"https://dns.lan:8443/dns-query"},
		},
		{
			"IPv6 字面量要加方括号",
			[]string{"::1"},
			8443,
			"/dns-query",
			[]string{"https://[::1]:8443/dns-query"},
		},
		{
			"路径缺前导斜杠时补齐",
			[]string{"dns.lan"},
			443,
			"resolve",
			[]string{"https://dns.lan/resolve"},
		},
		{
			"空路径回落默认值",
			[]string{"dns.lan"},
			443,
			"",
			[]string{"https://dns.lan/dns-query"},
		},
		{
			"丢弃空项与重复项",
			[]string{"dns.lan", "", "  ", "dns.lan", "192.168.1.5"},
			443,
			"/dns-query",
			[]string{"https://dns.lan/dns-query", "https://192.168.1.5/dns-query"},
		},
		{
			"非法端口回落默认端口",
			[]string{"dns.lan"},
			0,
			"/dns-query",
			[]string{"https://dns.lan/dns-query"},
		},
		{
			"无可用主机时返回空列表",
			[]string{"", "   "},
			443,
			"/dns-query",
			[]string{},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := DoHURLs(tc.hosts, tc.port, tc.path)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("DoHURLs(%v, %d, %q) = %v，期望 %v",
					tc.hosts, tc.port, tc.path, got, tc.want)
			}
		})
	}
}
