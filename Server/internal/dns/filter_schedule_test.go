package dns

import (
	"context"
	"net"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// scheduleFilterEngine 构建一个含单条拦截规则、且可注入时钟的过滤引擎。
func scheduleFilterEngine(t *testing.T) *core.RuleEngine {
	t.Helper()
	cfg := core.DefaultFilterConfig()
	cfg.DataDir = t.TempDir()
	cfg.Lists = []core.FilterList{}
	cfg.CustomRules = []string{"||ad.tracker.com^"}
	engine := core.NewRuleEngine(cfg)
	t.Cleanup(engine.Close)
	return engine
}

func TestFilterMiddlewareScheduleInactivePassesThrough(t *testing.T) {
	engine := scheduleFilterEngine(t)

	// 极窄窗口 00:00-00:01，并把时钟固定在窗口外的 12:00
	if err := engine.UpdateConfig(core.FilterConfig{
		Enabled:         true,
		ScheduleEnabled: true,
		Schedules: []core.BlockingSchedule{{
			ID: "narrow", Name: "极窄窗口", Enabled: true, Start: "00:00", End: "00:01",
		}},
	}); err != nil {
		t.Fatal(err)
	}
	engine.SetClock(func() time.Time {
		return time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local)
	})

	mw := NewFilterMiddleware(engine)

	req := new(dns.Msg)
	req.SetQuestion("ad.tracker.com.", dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	nextCalled := false
	if err := mw(ctx, func() error {
		nextCalled = true
		return nil
	}); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if !nextCalled {
		t.Fatalf("计划窗口外应放行并继续调用 next()")
	}
	if ctx.Resp != nil {
		t.Fatalf("窗口外不应生成拦截响应")
	}
	if v, ok := ctx.Get("filter_schedule_inactive"); !ok || v != true {
		t.Fatalf("应标记 filter_schedule_inactive，得到 %v", v)
	}
	if v, _ := ctx.Get("filter_blocked"); v == true {
		t.Fatalf("窗口外不应标记为拦截")
	}
}

func TestFilterMiddlewareScheduleActiveBlocks(t *testing.T) {
	engine := scheduleFilterEngine(t)

	// 全天窗口，时钟固定到任意时刻均在窗口内
	if err := engine.UpdateConfig(core.FilterConfig{
		Enabled:         true,
		ScheduleEnabled: true,
		Schedules: []core.BlockingSchedule{{
			ID: "all-day", Name: "全天", Enabled: true, Start: "00:00", End: "23:59",
		}},
	}); err != nil {
		t.Fatal(err)
	}
	engine.SetClock(func() time.Time {
		return time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local)
	})

	mw := NewFilterMiddleware(engine)

	req := new(dns.Msg)
	req.SetQuestion("ad.tracker.com.", dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	nextCalled := false
	if err := mw(ctx, func() error {
		nextCalled = true
		return nil
	}); err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	if nextCalled {
		t.Fatalf("窗口内被拦截不应调用 next()")
	}
	if ctx.Resp == nil {
		t.Fatalf("窗口内应生成拦截响应")
	}
	if v, _ := ctx.Get("filter_blocked"); v != true {
		t.Fatalf("应标记 filter_blocked")
	}
	if _, ok := ctx.Get("filter_schedule_inactive"); ok {
		t.Fatalf("窗口内不应标记 filter_schedule_inactive")
	}
}

// 服务级周计划窗口外只放行该服务，其余规则（含自定义规则）照常拦截
func TestFilterMiddlewareServiceScheduleInactive(t *testing.T) {
	engine := scheduleFilterEngine(t)

	if err := engine.UpdateConfig(core.FilterConfig{
		Enabled:         true,
		CustomRules:     []string{"||ad.tracker.com^"},
		BlockedServices: []string{"bilibili"},
		ServiceSchedules: map[string][]core.BlockingSchedule{
			"bilibili": {{ID: "school", Name: "上课时段", Enabled: true, Start: "00:00", End: "00:01"}},
		},
	}); err != nil {
		t.Fatal(err)
	}
	// 固定在极窄窗口之外
	engine.SetClock(func() time.Time {
		return time.Date(2026, 10, 12, 12, 0, 0, 0, time.Local)
	})

	mw := NewFilterMiddleware(engine)

	run := func(domain string) (nextCalled bool, ctx *DNSContext) {
		req := new(dns.Msg)
		req.SetQuestion(dns.Fqdn(domain), dns.TypeA)
		c := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")
		called := false
		if err := mw(c, func() error {
			called = true
			return nil
		}); err != nil {
			t.Fatalf("中间件返回错误: %v", err)
		}
		return called, c
	}

	called, ctx := run("bilibili.com")
	if !called || ctx.Resp != nil {
		t.Fatalf("服务计划窗口外应放行: nextCalled=%v, resp=%v", called, ctx.Resp)
	}
	if reason, _ := ctx.Get("filter_reason"); reason != core.ReasonServiceScheduleInactive {
		t.Fatalf("filter_reason = %v, want %v", reason, core.ReasonServiceScheduleInactive)
	}
	if blocked, _ := ctx.Get("filter_blocked"); blocked != false {
		t.Fatalf("窗口外不应标记为已拦截: %v", blocked)
	}

	// 同一时刻，其它规则不受服务计划影响
	called, ctx = run("ad.tracker.com")
	if called || ctx.Resp == nil {
		t.Fatalf("自定义规则应照常拦截: nextCalled=%v, resp=%v", called, ctx.Resp)
	}
}
