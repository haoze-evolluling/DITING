package core

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/miekg/dns"
)

// writeTestList 将列表内容写入规则缓存目录（避免测试触发外网拉取）。
func writeTestList(t *testing.T, dir, id, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, id+".txt"), []byte(body), 0o600); err != nil {
		t.Fatalf("写入列表缓存失败: %v", err)
	}
}

// groupEngine 构建一个含两条订阅列表的引擎，列表内容直接写入缓存文件避免外网拉取。
//
//   - list-ads  → ||ads.example.com^
//   - list-soc  → ||social.example.com^
func groupEngine(t *testing.T) *RuleEngine {
	t.Helper()
	dir := t.TempDir()

	writeTestList(t, dir, "list-ads", "||ads.example.com^\n")
	writeTestList(t, dir, "list-soc", "||social.example.com^\n")

	cfg := DefaultFilterConfig()
	cfg.DataDir = dir
	cfg.CustomRules = []string{"||custom.example.com^"}
	cfg.Lists = []FilterList{
		{ID: "list-ads", Name: "广告", Enabled: true},
		{ID: "list-soc", Name: "社交", Enabled: true},
	}

	engine := NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine
}

func TestRuleEngineGroupScopedLists(t *testing.T) {
	engine := groupEngine(t)

	// kids 组只绑定广告列表（自定义规则始终生效）
	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "kids", Name: "儿童", Enabled: true, RuleListIDs: []string{"list-ads"}},
			{ID: "work", Name: "办公", Enabled: true, RuleListIDs: []string{"list-soc"}},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	// kids 命中广告列表，但不命中社交列表
	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, "kids"); !res.Blocked {
		t.Fatalf("kids 组应命中广告列表: %+v", res)
	}
	if res := engine.MatchForGroup("social.example.com", dns.TypeA, "kids"); res.Blocked {
		t.Fatalf("kids 组不应命中未绑定的社交列表: %+v", res)
	}
	// 自定义规则对所有组生效
	if res := engine.MatchForGroup("custom.example.com", dns.TypeA, "kids"); !res.Blocked {
		t.Fatalf("kids 组应命中自定义规则: %+v", res)
	}

	// work 组反向：命中社交、不命中广告
	if res := engine.MatchForGroup("social.example.com", dns.TypeA, "work"); !res.Blocked {
		t.Fatalf("work 组应命中社交列表: %+v", res)
	}
	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, "work"); res.Blocked {
		t.Fatalf("work 组不应命中未绑定的广告列表: %+v", res)
	}
}

func TestRuleEngineGroupEmptyListsInheritAll(t *testing.T) {
	engine := groupEngine(t)

	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups:  []ClientGroup{{ID: "all", Name: "全量", Enabled: true}},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	for _, d := range []string{"ads.example.com", "social.example.com", "custom.example.com"} {
		if res := engine.MatchForGroup(d, dns.TypeA, "all"); !res.Blocked {
			t.Fatalf("空列表应继承全部规则, %s 未被拦截: %+v", d, res)
		}
	}
}

func TestRuleEngineDefaultGroupUnaffected(t *testing.T) {
	engine := groupEngine(t)

	// 启用分组后，default 组语义应与裸 Match 完全一致（使用全局全量规则）
	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups:  []ClientGroup{{ID: "kids", Enabled: true, RuleListIDs: []string{"list-ads"}}},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	for _, d := range []string{"ads.example.com", "social.example.com"} {
		base := engine.Match(d, dns.TypeA)
		grouped := engine.MatchForGroup(d, dns.TypeA, DefaultClientGroupID)
		if base.Blocked != grouped.Blocked {
			t.Fatalf("default 组行为偏离全局 Match: %s base=%v grouped=%v", d, base.Blocked, grouped.Blocked)
		}
	}

	// 未知分组同样回落默认匹配器
	if res := engine.MatchForGroup("social.example.com", dns.TypeA, "ghost"); !res.Blocked {
		t.Fatalf("未知分组应回落默认全量规则: %+v", res)
	}
}

func TestRuleEngineGroupBlockModeOverride(t *testing.T) {
	engine := groupEngine(t)

	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "strict", Enabled: true, BlockMode: BlockModeNXDOMAIN},
			{ID: "plain", Enabled: true},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	if got := engine.GroupBlockMode("strict"); got != BlockModeNXDOMAIN {
		t.Fatalf("strict 组应覆盖为 nxdomain, 得到 %q", got)
	}
	if got := engine.GroupBlockMode("plain"); got != "" {
		t.Fatalf("未配置覆盖的组应返回空串, 得到 %q", got)
	}
	if got := engine.GroupBlockMode(DefaultClientGroupID); got != "" {
		t.Fatalf("default 组不应有覆盖, 得到 %q", got)
	}
}

func TestRuleEngineSetClientGroupsHotReload(t *testing.T) {
	engine := groupEngine(t)

	// 初次：kids 仅绑定社交列表 → 广告域名不被拦截
	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups:  []ClientGroup{{ID: "kids", Enabled: true, RuleListIDs: []string{"list-soc"}}},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}
	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, "kids"); res.Blocked {
		t.Fatalf("初始配置不应拦截广告域名: %+v", res)
	}

	// 热更新为绑定广告列表 → 同一域名应变为拦截
	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups:  []ClientGroup{{ID: "kids", Enabled: true, RuleListIDs: []string{"list-ads"}}},
	}); err != nil {
		t.Fatalf("SetClientGroups 热更新失败: %v", err)
	}
	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, "kids"); !res.Blocked {
		t.Fatalf("热更新后应拦截广告域名: %+v", res)
	}

	// 关闭分组总开关 → 组匹配器清空，回落 default
	if err := engine.SetClientGroups(ClientGroupConfig{Enabled: false}); err != nil {
		t.Fatalf("禁用分组失败: %v", err)
	}
	got := engine.GetClientGroups()
	if got.Enabled || len(got.Groups) != 0 {
		t.Fatalf("禁用后配置应为空: %+v", got)
	}
}
