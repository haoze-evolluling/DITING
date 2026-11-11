package core

import (
	"testing"
	"time"

	"github.com/miekg/dns"
)

// groupPolicyEngine 构建含黑名单与白名单规则的分组引擎，用于计划/白名单策略测试。
//
//   - list-ads → ||ads.example.com^
//   - 自定义   → @@||trusted.example.com^
func groupPolicyEngine(t *testing.T) *RuleEngine {
	t.Helper()
	dir := t.TempDir()
	writeTestList(t, dir, "list-ads", "||ads.example.com^\n")

	cfg := DefaultFilterConfig()
	cfg.DataDir = dir
	cfg.CustomRules = []string{"@@||trusted.example.com^"}
	cfg.Lists = []FilterList{{ID: "list-ads", Name: "广告", Enabled: true}}

	engine := NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine
}

// groupPolicyClock 构造固定到某个星期的注入时钟。
func groupPolicyClock(weekday time.Weekday, hour, minute int) func() time.Time {
	// 2024-01-07 为周日，据此偏移得到目标星期
	base := time.Date(2024, time.January, 7, 0, 0, 0, 0, time.Local)
	target := base.AddDate(0, 0, int(weekday))
	return func() time.Time {
		return time.Date(target.Year(), target.Month(), target.Day(), hour, minute, 0, 0, time.Local)
	}
}

// TestGroupScheduleScopedToGroup 校验组级计划仅作用于配置了计划的分组。
func TestGroupScheduleScopedToGroup(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.SetClock(groupPolicyClock(time.Monday, 10, 0)) // 周一 10:00

	// kids 组：仅 08:00-09:00 生效 → 当前窗口外，整体放行
	// work 组：未配置组级计划 → 回落全局（全局未启用计划 = 常开）
	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{
				ID: "kids", Enabled: true,
				ScheduleEnabled: true,
				Schedules: []BlockingSchedule{
					{ID: "window", Name: "上学时段", Enabled: true, Weekdays: []string{"mon"}, Start: "08:00", End: "09:00"},
				},
			},
			{ID: "work", Enabled: true},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	res := engine.MatchForGroup("ads.example.com", dns.TypeA, "kids")
	if res.Blocked || res.Reason != ReasonScheduleInactive {
		t.Fatalf("kids 组在窗口外应整体放行, 得到 %+v", res)
	}

	// 同一时刻 work 组未配置组级计划 → 行为与全局一致，继续拦截
	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, "work"); !res.Blocked {
		t.Fatalf("未配置组级计划的组不应受组级计划影响: %+v", res)
	}
}

// TestGroupScheduleWithinWindow 校验组级计划窗口内恢复拦截。
func TestGroupScheduleWithinWindow(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.SetClock(groupPolicyClock(time.Monday, 8, 30)) // 周一 08:30，位于窗口内

	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{
				ID: "kids", Enabled: true,
				ScheduleEnabled: true,
				Schedules: []BlockingSchedule{
					{ID: "window", Name: "上学时段", Enabled: true, Weekdays: []string{"mon"}, Start: "08:00", End: "09:00"},
				},
			},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	if res := engine.MatchForGroup("ads.example.com", dns.TypeA, "kids"); !res.Blocked {
		t.Fatalf("窗口内应恢复拦截: %+v", res)
	}
	if !engine.IsBlockingActiveForGroup("kids") {
		t.Fatalf("窗口内 IsBlockingActiveForGroup 应为 true")
	}
}

// TestGroupScheduleCrossMidnight 校验跨夜窗口按窗口起始日归属星期。
func TestGroupScheduleCrossMidnight(t *testing.T) {
	engine := groupPolicyEngine(t)

	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{
				ID: "kids", Enabled: true,
				ScheduleEnabled: true,
				Schedules: []BlockingSchedule{
					{ID: "night", Name: "夜间", Enabled: true, Weekdays: []string{"mon"}, Start: "22:00", End: "06:00"},
				},
			},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	// 周一 23:00：窗口起始日内 → 生效
	engine.SetClock(groupPolicyClock(time.Monday, 23, 0))
	if !engine.IsBlockingActiveForGroup("kids") {
		t.Fatalf("周一 23:00 应处于跨夜窗口内")
	}

	// 周二 05:00：窗口延续（归属周一）→ 生效
	engine.SetClock(groupPolicyClock(time.Tuesday, 5, 0))
	if !engine.IsBlockingActiveForGroup("kids") {
		t.Fatalf("周二 05:00 应仍处于跨夜窗口内")
	}

	// 周二 07:00：窗口已结束 → 放行
	engine.SetClock(groupPolicyClock(time.Tuesday, 7, 0))
	if engine.IsBlockingActiveForGroup("kids") {
		t.Fatalf("周二 07:00 应已退出跨夜窗口")
	}
}

// TestGroupScheduleNormalizeDropsInvalid 校验非法组级计划被剔除且开关自动回落。
func TestGroupScheduleNormalizeDropsInvalid(t *testing.T) {
	cfg := ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{
				ID: "kids", Enabled: true, Clients: []string{"192.168.1.0/24"},
				ScheduleEnabled: true,
				Schedules: []BlockingSchedule{
					{ID: "bad", Name: "非法", Enabled: true, Weekdays: []string{"mon"}, Start: "99:99", End: "10:00"},
				},
			},
		},
	}
	if err := NormalizeClientGroupConfig(&cfg); err == nil {
		t.Fatalf("非法计划应报告归一化问题")
	}
	if len(cfg.Groups[0].Schedules) != 0 {
		t.Fatalf("非法计划应被丢弃, 得到 %v", cfg.Groups[0].Schedules)
	}
	if cfg.Groups[0].ScheduleEnabled {
		t.Fatalf("无可用计划时组级计划开关应自动关闭")
	}
}

// TestAllowlistOnlyGlobal 校验全局仅白名单模式下仅放行规则命中可通行。
func TestAllowlistOnlyGlobal(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.SetEnabled(true)

	cfg := engine.GetConfig()
	cfg.AllowlistOnly = true
	if err := engine.UpdateConfig(cfg); err != nil {
		t.Fatalf("UpdateConfig 失败: %v", err)
	}

	// 命中放行规则 → 放行
	res := engine.Match("trusted.example.com", dns.TypeA)
	if res.Blocked || res.Action != "allow" {
		t.Fatalf("白名单域名应放行, 得到 %+v", res)
	}

	// 命中黑名单 → 拦截（保持原原因）
	res = engine.Match("ads.example.com", dns.TypeA)
	if !res.Blocked || res.Reason != "blacklist" {
		t.Fatalf("黑名单域名应保持原拦截原因, 得到 %+v", res)
	}

	// 未命中任何规则 → 仅白名单模式下阻断
	res = engine.Match("unknown.example.com", dns.TypeA)
	if !res.Blocked || res.Reason != ReasonAllowlistOnly {
		t.Fatalf("未命中规则应因仅白名单模式被阻断, 得到 %+v", res)
	}
}

// TestAllowlistOnlyGroupOverride 校验组级仅白名单在全局关闭时仍可单独开启。
func TestAllowlistOnlyGroupOverride(t *testing.T) {
	engine := groupPolicyEngine(t)

	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{ID: "strict", Enabled: true, AllowlistOnly: true},
			{ID: "normal", Enabled: true},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	// strict 组：未命中规则 → 阻断
	res := engine.MatchForGroup("unknown.example.com", dns.TypeA, "strict")
	if !res.Blocked || res.Reason != ReasonAllowlistOnly {
		t.Fatalf("strict 组应因仅白名单模式阻断, 得到 %+v", res)
	}
	// strict 组：命中白名单 → 放行
	if res := engine.MatchForGroup("trusted.example.com", dns.TypeA, "strict"); res.Blocked {
		t.Fatalf("strict 组命中白名单应放行: %+v", res)
	}

	// normal 组：未开启该模式 → 未命中规则照常放行
	if res := engine.MatchForGroup("unknown.example.com", dns.TypeA, "normal"); res.Blocked {
		t.Fatalf("normal 组不应受仅白名单模式影响: %+v", res)
	}
}

// TestAllowlistOnlyCoexistsWithSchedule 校验计划窗口外整体放行优先于仅白名单模式。
func TestAllowlistOnlyCoexistsWithSchedule(t *testing.T) {
	engine := groupPolicyEngine(t)
	engine.SetClock(groupPolicyClock(time.Monday, 10, 0))

	if err := engine.SetClientGroups(ClientGroupConfig{
		Enabled: true,
		Groups: []ClientGroup{
			{
				ID: "kids", Enabled: true, AllowlistOnly: true,
				ScheduleEnabled: true,
				Schedules: []BlockingSchedule{
					{ID: "window", Name: "上学时段", Enabled: true, Weekdays: []string{"mon"}, Start: "08:00", End: "09:00"},
				},
			},
		},
	}); err != nil {
		t.Fatalf("SetClientGroups 失败: %v", err)
	}

	// 窗口外：即使开启仅白名单，也应整体放行
	res := engine.MatchForGroup("unknown.example.com", dns.TypeA, "kids")
	if res.Blocked || res.Reason != ReasonScheduleInactive {
		t.Fatalf("计划窗口外应优先整体放行, 得到 %+v", res)
	}
}
