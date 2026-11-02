package core

import (
	"testing"

	"github.com/miekg/dns"
)

func TestServicesCatalog_LoadsEmbeddedData(t *testing.T) {
	services, groups := ServicesCatalog()
	if len(services) == 0 {
		t.Fatal("内置服务目录为空，embed 数据可能未打包")
	}
	if len(groups) == 0 {
		t.Fatal("服务分组为空")
	}

	// 分组计数必须与服务归属一致，否则界面上的分组徽标会凭空多出条目
	counts := map[string]int{}
	for _, s := range services {
		counts[s.Group]++
	}
	for _, g := range groups {
		if counts[g.ID] != g.Count {
			t.Fatalf("分组 %s 的计数 = %d, want %d", g.ID, g.Count, counts[g.ID])
		}
		if g.Name == "" {
			t.Fatalf("分组 %s 缺少显示名", g.ID)
		}
	}
}

func TestServicesCatalog_EveryServiceHasUsableRules(t *testing.T) {
	services, _ := ServicesCatalog()
	for _, s := range services {
		if s.ID == "" || s.Name == "" {
			t.Fatalf("服务缺少 ID 或名称: %+v", s)
		}
		if s.RuleN == 0 {
			t.Fatalf("服务 %s (%s) 展开后没有任何可用规则", s.ID, s.Name)
		}
		if s.Source != serviceRuleSourcePrefix+s.ID {
			t.Fatalf("服务 %s 的 Source = %q", s.ID, s.Source)
		}
	}
}

func TestServicesCatalog_SortedByGroupThenName(t *testing.T) {
	services, groups := ServicesCatalog()
	order := make(map[string]int, len(groups))
	for i, g := range groups {
		order[g.ID] = i
	}
	for i := 1; i < len(services); i++ {
		prev, cur := services[i-1], services[i]
		if order[prev.Group] > order[cur.Group] {
			t.Fatalf("服务未按分组排序: %s(%s) 在 %s(%s) 之前",
				prev.ID, prev.Group, cur.ID, cur.Group)
		}
		if prev.Group == cur.Group && prev.Name > cur.Name {
			t.Fatalf("同组内服务未按名称排序: %s 在 %s 之前", prev.Name, cur.Name)
		}
	}
}

// 目录中的服务 ID 必须唯一，否则勾选状态会串到同名服务上
func TestServicesCatalog_IDsUnique(t *testing.T) {
	services, _ := ServicesCatalog()
	seen := make(map[string]bool, len(services))
	for _, s := range services {
		if seen[s.ID] {
			t.Fatalf("服务 ID 重复: %s", s.ID)
		}
		seen[s.ID] = true
	}
}

func TestServiceExists(t *testing.T) {
	services, _ := ServicesCatalog()
	if len(services) == 0 {
		t.Skip("目录为空")
	}
	if !ServiceExists(services[0].ID) {
		t.Fatalf("目录中的服务 %s 应被识别", services[0].ID)
	}
	if ServiceExists("definitely-not-a-service") {
		t.Fatal("未知服务 ID 不应被识别")
	}
}

func TestServiceGroupExists(t *testing.T) {
	_, groups := ServicesCatalog()
	if len(groups) == 0 {
		t.Skip("目录为空")
	}
	if !ServiceGroupExists(groups[0].ID) {
		t.Fatalf("目录中的分组 %s 应被识别", groups[0].ID)
	}
	if ServiceGroupExists("definitely-not-a-group") {
		t.Fatal("未知分组 ID 不应被识别")
	}
}

// ---------------------------------------------------------------------------
// 勾选 → 规则的展开
// ---------------------------------------------------------------------------

func serviceEngine(t *testing.T, cfg FilterConfig) *RuleEngine {
	t.Helper()
	cfg.Enabled = true
	cfg.DataDir = t.TempDir()
	return NewRuleEngine(cfg)
}

func TestBlockedServices_SingleServiceBlocks(t *testing.T) {
	engine := serviceEngine(t, FilterConfig{BlockedServices: []string{"bilibili"}})
	defer engine.Close()

	res := engine.Match("bilibili.com", dns.TypeA)
	if !res.Blocked {
		t.Fatalf("bilibili.com 应被拦截: %+v", res)
	}
	if res.ListName != serviceRuleSourcePrefix+"bilibili" {
		t.Fatalf("来源 = %q, want service:bilibili", res.ListName)
	}

	// 未勾选的服务不受影响
	if res := engine.Match("example.org", dns.TypeA); res.Blocked {
		t.Fatalf("未勾选的服务不应被拦截: %+v", res)
	}
}

func TestBlockedServices_GroupBlocksAllMembers(t *testing.T) {
	engine := serviceEngine(t, FilterConfig{BlockedServiceGroups: []string{"short_video"}})
	defer engine.Close()

	// 同组两个服务都应被拦下
	for _, domain := range []string{"douyin.com", "kuaishou.com"} {
		if res := engine.Match(domain, dns.TypeA); !res.Blocked {
			t.Fatalf("%s 应随分组被拦截: %+v", domain, res)
		}
	}
	if res := engine.Match("wikipedia.org", dns.TypeA); res.Blocked {
		t.Fatalf("组外域名不应被拦截: %+v", res)
	}
}

func TestBlockedServices_ServiceAndGroupUnion(t *testing.T) {
	// 服务与分组取并集：只勾服务时不应连带整组
	engine := serviceEngine(t, FilterConfig{BlockedServices: []string{"bilibili"}})
	defer engine.Close()

	if res := engine.Match("kuaishou.com", dns.TypeA); res.Blocked {
		t.Fatalf("仅勾选服务时同组其它服务不应被拦截: %+v", res)
	}
}

func TestBlockedServices_DisabledServicePasses(t *testing.T) {
	engine := serviceEngine(t, FilterConfig{})
	defer engine.Close()

	if res := engine.Match("bilibili.com", dns.TypeA); res.Blocked {
		t.Fatalf("未勾选任何服务时不应拦截: %+v", res)
	}
}

// 取消勾选必须让规则真正消失，而不是留在索引里继续拦截
func TestBlockedServices_UpdateRemovesBlocks(t *testing.T) {
	engine := serviceEngine(t, FilterConfig{BlockedServices: []string{"bilibili"}})
	defer engine.Close()

	if res := engine.Match("bilibili.com", dns.TypeA); !res.Blocked {
		t.Fatal("更新前应处于拦截状态")
	}

	cfg := engine.GetConfig()
	cfg.BlockedServices = nil
	if err := engine.UpdateConfig(cfg); err != nil {
		t.Fatalf("更新配置失败: %v", err)
	}

	if res := engine.Match("bilibili.com", dns.TypeA); res.Blocked {
		t.Fatalf("取消勾选后不应再拦截: %+v", res)
	}
}

// 换一个服务（长度不变）也必须触发索引重建
func TestBlockedServices_SwapOneForAnother(t *testing.T) {
	engine := serviceEngine(t, FilterConfig{BlockedServices: []string{"bilibili"}})
	defer engine.Close()

	cfg := engine.GetConfig()
	cfg.BlockedServices = []string{"zhihu"}
	if err := engine.UpdateConfig(cfg); err != nil {
		t.Fatalf("更新配置失败: %v", err)
	}

	if res := engine.Match("bilibili.com", dns.TypeA); res.Blocked {
		t.Fatalf("被换掉的服务不应再拦截: %+v", res)
	}
	if res := engine.Match("zhihu.com", dns.TypeA); !res.Blocked {
		t.Fatalf("新勾选的服务应被拦截: %+v", res)
	}
}

// 自定义规则优先级高于内置服务，用户写下的例外必须能生效
func TestBlockedServices_CustomAllowRuleWins(t *testing.T) {
	engine := serviceEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili"},
		CustomRules:     []string{"@@||bilibili.com^"},
	})
	defer engine.Close()

	res := engine.Match("bilibili.com", dns.TypeA)
	if res.Blocked || res.Action != "allow" {
		t.Fatalf("例外规则应放行 bilibili.com: %+v", res)
	}
}

func TestCountBlockedServiceRules(t *testing.T) {
	// 分组与其中某个服务同时勾选时不应重复计数
	one := CountBlockedServiceRules([]string{"douyin"}, nil)
	group := CountBlockedServiceRules(nil, []string{"short_video"})
	both := CountBlockedServiceRules([]string{"douyin"}, []string{"short_video"})

	if one == 0 || group == 0 {
		t.Fatalf("单项与分组都应展开出规则: %d / %d", one, group)
	}
	if both != group {
		t.Fatalf("重复勾选后规则数 = %d, want %d（应与仅勾分组一致）", both, group)
	}
	if CountBlockedServiceRules(nil, nil) != 0 {
		t.Fatal("空选择应展开出 0 条规则")
	}
}

// 目录里的服务规则必须真的能拦住对应域名，而不是仅存在于清单中
func TestBlockedServices_EveryServiceRuleParses(t *testing.T) {
	services, _ := ServicesCatalog()
	for _, s := range services {
		if s.RuleN != len(s.Rules) {
			t.Fatalf("服务 %s 有 %d 条规则，仅 %d 条解析成功", s.ID, len(s.Rules), s.RuleN)
		}
	}
}
