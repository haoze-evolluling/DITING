package core

import (
	"net"
	"testing"
)

func TestGroupResolverLongestPrefixWins(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "lan", Name: "局域网", Enabled: true, Clients: []string{"192.168.0.0/16"}},
			{ID: "kids", Name: "儿童房", Enabled: true, Clients: []string{"192.168.1.0/24"}},
		},
	}
	r, err := NewGroupResolver(cfg)
	if err != nil {
		t.Fatalf("编译分组失败: %v", err)
	}
	if r.Size() != 2 {
		t.Fatalf("期望 2 个成员条目, 得到 %d", r.Size())
	}

	// /24 比 /16 更具体，应命中 kids
	if got := r.Resolve(net.ParseIP("192.168.1.50")); got != "kids" {
		t.Fatalf("192.168.1.50 应命中 kids, 得到 %s", got)
	}
	// 落在 /16 但不在 /24 内，命中 lan
	if got := r.Resolve(net.ParseIP("192.168.5.10")); got != "lan" {
		t.Fatalf("192.168.5.10 应命中 lan, 得到 %s", got)
	}
	// 完全未覆盖的地址回落 default
	if got := r.Resolve(net.ParseIP("10.0.0.1")); got != DefaultClientGroupID {
		t.Fatalf("10.0.0.1 应回落 %s, 得到 %s", DefaultClientGroupID, got)
	}
}

func TestGroupResolverSingleIPAndIPv6(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "host-a", Enabled: true, Clients: []string{"10.0.0.7"}},
			{ID: "v6net", Enabled: true, Clients: []string{"fd00::/8"}},
		},
	}
	r, err := NewGroupResolver(cfg)
	if err != nil {
		t.Fatalf("编译分组失败: %v", err)
	}

	if got := r.Resolve(net.ParseIP("10.0.0.7")); got != "host-a" {
		t.Fatalf("单 IP 精确命中失败, 得到 %s", got)
	}
	if got := r.Resolve(net.ParseIP("10.0.0.8")); got != DefaultClientGroupID {
		t.Fatalf("相邻 IP 不应命中 host-a, 得到 %s", got)
	}
	if got := r.Resolve(net.ParseIP("fd00::1")); got != "v6net" {
		t.Fatalf("IPv6 前缀命中失败, 得到 %s", got)
	}
	if got := r.Resolve(net.ParseIP("fd00:abcd::99")); got != "v6net" {
		t.Fatalf("IPv6 前缀范围内应命中, 得到 %s", got)
	}
}

func TestGroupResolverDisabledYieldsDefault(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: false,
		Groups:  []ClientGroup{{ID: "lan", Enabled: true, Clients: []string{"192.168.0.0/16"}}},
	}
	r, err := NewGroupResolver(cfg)
	if err != nil {
		t.Fatalf("禁用分组不应报错: %v", err)
	}
	if r.Size() != 0 {
		t.Fatalf("禁用时不应编译任何条目, 得到 %d", r.Size())
	}
	if got := r.Resolve(net.ParseIP("192.168.1.1")); got != DefaultClientGroupID {
		t.Fatalf("禁用分组应永远回落 default, 得到 %s", got)
	}
}

func TestGroupResolverSkipsDisabledGroupAndNilIP(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "off", Enabled: false, Clients: []string{"172.16.0.0/12"}},
			{ID: "on", Enabled: true, Clients: []string{"172.16.0.0/12"}},
		},
	}
	r, _ := NewGroupResolver(cfg)
	if got := r.Resolve(net.ParseIP("172.16.1.1")); got != "on" {
		t.Fatalf("仅启用组应生效, 得到 %s", got)
	}
	var nilIP net.IP
	if got := r.Resolve(nilIP); got != DefaultClientGroupID {
		t.Fatalf("nil IP 应回落 default, 得到 %s", got)
	}
	var nilResolver *GroupResolver
	if got := nilResolver.Resolve(net.ParseIP("1.2.3.4")); got != DefaultClientGroupID {
		t.Fatalf("nil resolver 应回落 default, 得到 %s", got)
	}
}

func TestNormalizeClientGroupConfigFixesProblems(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "", Name: "  自动命名  ", Enabled: true, Clients: []string{"192.168.1.5", "bad-ip", "  "}},
			{ID: "dup", Name: "A", Enabled: true, Clients: []string{"10.0.0.0/8"}},
			{ID: "dup", Name: "B", Enabled: true, Clients: []string{"10.1.0.0/16"}},
			{ID: DefaultClientGroupID, Name: "保留字冲突", Enabled: true},
			{ID: "mode", Name: "C", Enabled: true, Clients: []string{"10.2.0.0/16"}, BlockMode: "bogus"},
		},
	}
	err := NormalizeClientGroupConfig(&cfg)
	if err == nil {
		t.Fatalf("应报告归一化问题")
	}

	// 空 ID 自动补全、非法成员被剔除
	if cfg.Groups[0].ID != "group-1" {
		t.Fatalf("空 ID 应自动补为 group-1, 得到 %q", cfg.Groups[0].ID)
	}
	if cfg.Groups[0].Name != "自动命名" {
		t.Fatalf("名称应被 trim, 得到 %q", cfg.Groups[0].Name)
	}
	if len(cfg.Groups[0].Clients) != 1 || cfg.Groups[0].Clients[0] != "192.168.1.5" {
		t.Fatalf("非法成员应被剔除, 得到 %v", cfg.Groups[0].Clients)
	}

	// 重复 ID 与保留字分组被丢弃 → 剩余 group-1 / dup / mode
	if len(cfg.Groups) != 3 {
		t.Fatalf("期望剩余 3 个分组, 得到 %d: %+v", len(cfg.Groups), cfg.Groups)
	}

	// 非法拦截方式被清空（回落全局）
	last := cfg.Groups[2]
	if last.BlockMode != "" {
		t.Fatalf("非法拦截方式应被清空, 得到 %q", last.BlockMode)
	}
}

func TestClientConfigNormalizeAndGroupConfig(t *testing.T) {
	c := ClientConfig{
		GroupsEnabled: true,
		Groups:        []ClientGroup{{ID: "kids", Enabled: true, Clients: []string{"192.168.1.0/24"}}},
	}
	gc := c.GroupConfig()
	if !gc.Enabled || len(gc.Groups) != 1 {
		t.Fatalf("GroupConfig 提取失败: %+v", gc)
	}

	if err := c.Normalize(); err != nil {
		t.Fatalf("合法配置归一化不应报错: %v", err)
	}
	if len(c.Groups) != 1 || c.Groups[0].ID != "kids" {
		t.Fatalf("归一化后分组应保留, 得到 %+v", c.Groups)
	}

	// 空 Groups 时 GroupConfig 返回非 nil 空切片
	empty := ClientConfig{}
	if g := empty.GroupConfig(); g.Groups == nil {
		t.Fatalf("空配置应返回非 nil 切片")
	}
}

func TestIsValidBlockMode(t *testing.T) {
	valid := []string{BlockModeNullIP, BlockModeNXDOMAIN, BlockModeRefused}
	for _, m := range valid {
		if !IsValidBlockMode(m) {
			t.Fatalf("%q 应视为合法拦截方式", m)
		}
	}
	for _, m := range []string{"", "bogus", "NULL"} {
		if IsValidBlockMode(m) {
			t.Fatalf("%q 不应视为合法拦截方式", m)
		}
	}
}
