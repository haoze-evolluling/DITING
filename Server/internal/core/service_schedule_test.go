package core

import (
	"testing"
	"time"

	"github.com/miekg/dns"
)

// rfcTestTime 构造一个可读的本地时刻，便于按「星期 + 时刻」书写用例
func rfcTestTime(weekday time.Weekday, hour, minute int) time.Time {
	// 2026-10-12 是周一
	base := time.Date(2026, 10, 12, hour, minute, 0, 0, time.Local)
	return base.AddDate(0, 0, int(weekday)-int(time.Monday))
}

// weekdayWindow 构造一条「指定星期 08:00-18:00」的计划
func weekdayWindow(days []string) []BlockingSchedule {
	return []BlockingSchedule{{
		ID: "school", Name: "上课时段", Enabled: true,
		Weekdays: days, Start: "08:00", End: "18:00",
	}}
}

func svcScheduleEngine(t *testing.T, cfg FilterConfig) (*RuleEngine, *time.Time) {
	t.Helper()
	cfg.Enabled = true
	cfg.DataDir = t.TempDir()
	engine := NewRuleEngine(cfg)

	now := rfcTestTime(time.Monday, 10, 0)
	engine.SetClock(func() time.Time { return now })
	return engine, &now
}

func TestServiceSchedule_BlocksInsideWindow(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": weekdayWindow(nil), // 空星期 = 每天
		},
	})
	defer engine.Close()

	*now = rfcTestTime(time.Wednesday, 10, 0)
	if res := engine.Match("bilibili.com", dns.TypeA); !res.Blocked {
		t.Fatalf("窗口内应拦截: %+v", res)
	}
}

func TestServiceSchedule_PassesOutsideWindow(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": weekdayWindow([]string{"mon", "tue", "wed", "thu", "fri"}),
		},
	})
	defer engine.Close()

	// 周日不在生效星期内
	*now = rfcTestTime(time.Sunday, 10, 0)
	res := engine.Match("bilibili.com", dns.TypeA)
	if res.Blocked {
		t.Fatalf("窗口外不应拦截: %+v", res)
	}
	if res.Reason != ReasonServiceScheduleInactive {
		t.Fatalf("原因 = %q, want %q", res.Reason, ReasonServiceScheduleInactive)
	}

	// 同一服务在生效星期内仍应拦截，确认放行确实来自计划而非配置丢失
	*now = rfcTestTime(time.Monday, 10, 0)
	if res := engine.Match("bilibili.com", dns.TypeA); !res.Blocked {
		t.Fatalf("窗口内应拦截: %+v", res)
	}
}

func TestServiceSchedule_OtherServicesUnaffected(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili", "zhihu"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": weekdayWindow([]string{"mon"}),
		},
	})
	defer engine.Close()

	// 周日：bilibili 放行，未配置计划的 zhihu 照常拦截
	*now = rfcTestTime(time.Sunday, 10, 0)
	if res := engine.Match("bilibili.com", dns.TypeA); res.Blocked {
		t.Fatalf("bilibili 在窗口外应放行: %+v", res)
	}
	if res := engine.Match("zhihu.com", dns.TypeA); !res.Blocked {
		t.Fatalf("未配置计划的服务应照常拦截: %+v", res)
	}
}

// 没有任何启用计划时恒为生效，与全局计划语义一致
func TestServiceSchedule_NoEnabledScheduleAlwaysBlocks(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": {{
				ID: "off", Name: "已停用", Enabled: false,
				Start: "08:00", End: "18:00",
			}},
		},
	})
	defer engine.Close()

	*now = rfcTestTime(time.Sunday, 3, 0)
	if res := engine.Match("bilibili.com", dns.TypeA); !res.Blocked {
		t.Fatalf("计划全部停用时应恒为拦截: %+v", res)
	}
}

func TestServiceSchedule_NonServiceRulesUnaffected(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices:  []string{"bilibili"},
		CustomRules:      []string{"||ads.example^"},
		ServiceSchedules: map[string][]BlockingSchedule{"bilibili": weekdayWindow([]string{"mon"})},
	})
	defer engine.Close()

	*now = rfcTestTime(time.Sunday, 10, 0)
	if res := engine.Match("ads.example", dns.TypeA); !res.Blocked {
		t.Fatalf("自定义规则不应受服务计划影响: %+v", res)
	}
}

// 跨夜窗口在次日凌晨仍应处于拦截状态
func TestServiceSchedule_OvernightWindow(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": {{
				ID: "night", Name: "夜间", Enabled: true,
				Start: "22:00", End: "06:00",
			}},
		},
	})
	defer engine.Close()

	*now = rfcTestTime(time.Tuesday, 2, 0)
	if res := engine.Match("bilibili.com", dns.TypeA); !res.Blocked {
		t.Fatalf("跨夜窗口内应拦截: %+v", res)
	}

	*now = rfcTestTime(time.Tuesday, 12, 0)
	if res := engine.Match("bilibili.com", dns.TypeA); res.Blocked {
		t.Fatalf("跨夜窗口外应放行: %+v", res)
	}
}

// 例外规则优先级高于服务规则，计划放行不应让例外规则失效，反之亦然
func TestServiceSchedule_AllowRuleStillWins(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili"},
		CustomRules:     []string{"@@||bilibili.com^"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": weekdayWindow(nil),
		},
	})
	defer engine.Close()

	*now = rfcTestTime(time.Monday, 10, 0)
	res := engine.Match("bilibili.com", dns.TypeA)
	if res.Blocked || res.Action != "allow" {
		t.Fatalf("例外规则应始终放行: %+v", res)
	}
}

// ---------------------------------------------------------------------------
// 配置归一化
// ---------------------------------------------------------------------------

func TestNormalizeServiceSchedules_DropsUnknownServices(t *testing.T) {
	out := NormalizeServiceSchedules(map[string][]BlockingSchedule{
		"definitely-not-a-service": weekdayWindow(nil),
		"bilibili":                 weekdayWindow(nil),
	})
	if _, ok := out["definitely-not-a-service"]; ok {
		t.Fatal("未知服务的计划应被丢弃")
	}
	if len(out["bilibili"]) != 1 {
		t.Fatalf("已知服务的计划应保留: %+v", out)
	}
}

func TestNormalizeServiceSchedules_DropsInvalidEntries(t *testing.T) {
	out := NormalizeServiceSchedules(map[string][]BlockingSchedule{
		"bilibili": {
			{ID: "bad", Enabled: true, Start: "25:00", End: "26:00"},
			{ID: "good", Name: "有效", Enabled: true, Start: "08:00", End: "18:00"},
		},
	})
	if len(out["bilibili"]) != 1 || out["bilibili"][0].ID != "good" {
		t.Fatalf("非法计划应被丢弃、合法计划应保留: %+v", out)
	}
}

func TestNormalizeServiceSchedules_EmptyReturnsNil(t *testing.T) {
	if NormalizeServiceSchedules(nil) != nil {
		t.Fatal("空输入应返回 nil")
	}
	// 全部条目都非法时也不应留下空表，避免配置里出现无意义的键
	if out := NormalizeServiceSchedules(map[string][]BlockingSchedule{
		"bilibili": {{ID: "bad", Start: "99:99"}},
	}); out != nil {
		t.Fatalf("全部非法时应返回 nil, got %+v", out)
	}
}

// FilterConfig 归一化必须把服务计划一并编译，否则查询期用的是未编译的零值
func TestNormalizeFilterConfig_CompilesServiceSchedules(t *testing.T) {
	cfg := DefaultFilterConfig()
	cfg.BlockedServices = []string{"bilibili"}
	cfg.ServiceSchedules = map[string][]BlockingSchedule{
		"bilibili": {{
			ID: "school", Name: "上课", Enabled: true,
			Weekdays: []string{"mon"}, Start: "08:00", End: "18:00",
		}},
	}
	cfg.BlockedServices = filterKnownIDs(cfg.BlockedServices, ServiceExists, "服务")
	NormalizeFilterConfig(&cfg)

	compiled := cfg.ServiceSchedules["bilibili"]
	if len(compiled) != 1 {
		t.Fatalf("计划未保留: %+v", cfg.ServiceSchedules)
	}
	// 周一 10:00 命中；周日不命中——能判定即说明编译产物已写入
	if !compiled[0].IsActive(rfcTestTime(time.Monday, 10, 0)) {
		t.Fatal("计划未编译：周一 10:00 应命中")
	}
	if compiled[0].IsActive(rfcTestTime(time.Sunday, 10, 0)) {
		t.Fatal("计划未编译：周日不应命中")
	}
}

// ---------------------------------------------------------------------------
// 状态查询
// ---------------------------------------------------------------------------

func TestServiceScheduleStates(t *testing.T) {
	engine, now := svcScheduleEngine(t, FilterConfig{
		BlockedServices: []string{"bilibili", "zhihu"},
		ServiceSchedules: map[string][]BlockingSchedule{
			"bilibili": weekdayWindow([]string{"mon"}),
			"zhihu":    {{ID: "paused", Name: "停用中", Enabled: false, Start: "08:00", End: "18:00"}},
		},
	})
	defer engine.Close()

	*now = rfcTestTime(time.Monday, 10, 0)
	states := engine.ServiceScheduleStates()
	if len(states) != 2 {
		t.Fatalf("状态数量 = %d, want 2", len(states))
	}
	// sortedKeys 保证 ID 升序，输出稳定
	if states[0].ServiceID != "bilibili" || states[1].ServiceID != "zhihu" {
		t.Fatalf("状态未按服务 ID 排序: %+v", states)
	}
	if !states[0].Active || states[0].ActiveName != "上课时段" {
		t.Fatalf("bilibili 应处于生效窗口: %+v", states[0])
	}
	// 无启用计划视为恒生效，但仍要如实标注「没有计划」
	if !states[1].Active || states[1].HasSchedule {
		t.Fatalf("zhihu 应恒生效且无启用计划: %+v", states[1])
	}
}

func TestGetServiceSchedules_ReturnsCopy(t *testing.T) {
	engine, _ := svcScheduleEngine(t, FilterConfig{
		BlockedServices:  []string{"bilibili"},
		ServiceSchedules: map[string][]BlockingSchedule{"bilibili": weekdayWindow(nil)},
	})
	defer engine.Close()

	got := engine.GetServiceSchedules()
	got["bilibili"][0].Start = "00:00"

	again := engine.GetServiceSchedules()
	if again["bilibili"][0].Start != "08:00" {
		t.Fatal("GetServiceSchedules 应返回副本，外部改写不应影响引擎")
	}
}

func TestServiceIDFromSource(t *testing.T) {
	for _, tc := range []struct {
		source string
		want   string
		ok     bool
	}{
		{"service:bilibili", "bilibili", true},
		{"service:douyin", "douyin", true},
		{"custom", "", false},
		{"adguard-dns-filter", "", false},
		{"service:", "", false},
		{"service:   ", "", false},
	} {
		got, ok := ServiceIDFromSource(tc.source)
		if ok != tc.ok || got != tc.want {
			t.Fatalf("ServiceIDFromSource(%q) = %q, %v; want %q, %v", tc.source, got, ok, tc.want, tc.ok)
		}
	}
}
