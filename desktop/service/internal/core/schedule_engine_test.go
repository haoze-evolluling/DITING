package core

import (
	"testing"
	"time"
)

// scheduleEngine 构造一个仅启用自定义规则的引擎（不拉取外网订阅）。
func scheduleEngine(t *testing.T) *RuleEngine {
	t.Helper()
	cfg := DefaultFilterConfig()
	cfg.DataDir = t.TempDir()
	cfg.Lists = []FilterList{}
	cfg.CustomRules = []string{"||tracker.example^"}
	engine := NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine
}

func TestRuleEngineMatchInactiveSchedulePasses(t *testing.T) {
	engine := scheduleEngine(t)

	// 启用计划：仅在 00:00-00:01 生效 —— 用已过期窗口保证当前不在窗口内
	enabled := true
	schedules := []BlockingSchedule{{
		ID: "narrow", Name: "极窄窗口", Enabled: true,
		Start: "00:00", End: "00:01",
	}}
	if err := engine.UpdateConfig(FilterConfig{
		Enabled:         true,
		ScheduleEnabled: enabled,
		Schedules:       schedules,
	}); err != nil {
		t.Fatalf("UpdateConfig 失败: %v", err)
	}

	// 强制当前时间为窗口外（12:00）
	now := time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local)
	engine.SetClock(func() time.Time { return now })
	if got := engine.IsBlockingActiveAt(now); got {
		t.Fatalf("12:00 不应处于极窄窗口内")
	}

	before := engine.GetStats().BlockedQueries
	res := engine.Match("tracker.example", 1)
	if res.Blocked {
		t.Fatalf("计划窗口外不应拦截，得到 %+v", res)
	}
	if res.Action != "pass" || res.Reason != ReasonScheduleInactive {
		t.Fatalf("窗口外应返回 pass + %s，得到 %+v", ReasonScheduleInactive, res)
	}
	if engine.GetStats().BlockedQueries != before {
		t.Fatalf("窗口外放行不应增加拦截计数")
	}
}

func TestRuleEngineMatchActiveScheduleBlocks(t *testing.T) {
	engine := scheduleEngine(t)
	if err := engine.UpdateConfig(FilterConfig{
		Enabled:         true,
		ScheduleEnabled: true,
		Schedules: []BlockingSchedule{{
			ID: "all-day", Name: "全天", Enabled: true,
			Start: "00:00", End: "23:59",
		}},
	}); err != nil {
		t.Fatal(err)
	}

	// 固定时钟到窗口内，避免真实时间落在 23:59 边界导致断言偶发失败
	engine.SetClock(func() time.Time { return time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local) })

	before := engine.GetStats().BlockedQueries
	res := engine.Match("tracker.example", 1)
	if !res.Blocked {
		t.Fatalf("窗口内应命中拦截规则，得到 %+v", res)
	}
	if engine.GetStats().BlockedQueries != before+1 {
		t.Fatalf("窗口内拦截应计数一次")
	}
}

func TestRuleEngineScheduleDisabledKeepsBlockingAlwaysOn(t *testing.T) {
	engine := scheduleEngine(t)
	// 计划列表非空但总开关关闭 → 视为常开
	if err := engine.UpdateConfig(FilterConfig{
		Enabled:         true,
		ScheduleEnabled: false,
		Schedules: []BlockingSchedule{{
			ID: "narrow", Enabled: true, Start: "00:00", End: "00:01",
		}},
	}); err != nil {
		t.Fatal(err)
	}

	if !engine.IsBlockingActiveAt(time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local)) {
		t.Fatalf("计划总开关关闭时应恒为生效")
	}
	res := engine.Match("tracker.example", 1)
	if !res.Blocked {
		t.Fatalf("总开关关闭时应保持拦截，得到 %+v", res)
	}
}

func TestRuleEngineScheduleNoEnabledEntriesKeepsBlockingOn(t *testing.T) {
	engine := scheduleEngine(t)
	if err := engine.UpdateConfig(FilterConfig{
		Enabled:         true,
		ScheduleEnabled: true,
		Schedules: []BlockingSchedule{{
			ID: "disabled-row", Enabled: false, Start: "00:00", End: "00:01",
		}},
	}); err != nil {
		t.Fatal(err)
	}

	if !engine.IsBlockingActiveAt(time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local)) {
		t.Fatalf("无启用计划时应恒为生效（等价常开）")
	}
	if !engine.Match("tracker.example", 1).Blocked {
		t.Fatalf("无启用计划时应保持拦截")
	}
}

func TestRuleEngineCheckHostIgnoresSchedule(t *testing.T) {
	engine := scheduleEngine(t)
	if err := engine.UpdateConfig(FilterConfig{
		Enabled:         true,
		ScheduleEnabled: true,
		Schedules: []BlockingSchedule{{
			ID: "narrow", Enabled: true, Start: "00:00", End: "00:01",
		}},
	}); err != nil {
		t.Fatal(err)
	}

	// 手工检测（规则检测 UI）应始终反映规则本身，与日历无关
	res := engine.CheckHost("tracker.example", 1)
	if !res.Blocked {
		t.Fatalf("CheckHost 应保持与计划无关，得到 %+v", res)
	}
}

func TestNormalizeFilterConfigDropsInvalidSchedules(t *testing.T) {
	cfg := DefaultFilterConfig()
	cfg.Schedules = []BlockingSchedule{
		{ID: "ok", Name: "合法", Enabled: true, Start: "08:00", End: "09:00"},
		{ID: "bad", Name: "非法", Enabled: true, Start: "99:99", End: "10:00"},
	}
	NormalizeFilterConfig(&cfg)

	if len(cfg.Schedules) != 1 || cfg.Schedules[0].ID != "ok" {
		t.Fatalf("应丢弃非法计划，仅保留合法项，得到 %+v", cfg.Schedules)
	}
	if cfg.Schedules[0].startMin != 8*60 {
		t.Fatalf("合法计划应完成编译，得到 startMin=%d", cfg.Schedules[0].startMin)
	}
}

func TestRuleEngineUpdateScheduleWithoutRebuild(t *testing.T) {
	engine := scheduleEngine(t)
	rulesBefore := engine.GetStats().TotalRules
	if rulesBefore == 0 {
		t.Fatalf("预设自定义规则应已构建")
	}

	// 仅更新时间计划：不应触发规则索引重建（规则数保持一致）
	if err := engine.UpdateConfig(FilterConfig{
		Enabled:         true,
		ScheduleEnabled: true,
		Schedules: []BlockingSchedule{{
			ID: "s", Enabled: true, Start: "08:00", End: "18:00",
		}},
	}); err != nil {
		t.Fatal(err)
	}

	stats := engine.GetStats()
	if stats.TotalRules != rulesBefore {
		t.Fatalf("时间计划热更新不应改变规则数：before=%d after=%d", rulesBefore, stats.TotalRules)
	}
	if got := engine.GetConfig().CustomRules; len(got) != 1 {
		t.Fatalf("部分更新应保留既有自定义规则，得到 %v", got)
	}
}
