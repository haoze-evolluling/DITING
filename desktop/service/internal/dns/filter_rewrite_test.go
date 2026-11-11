package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// rewriteTestEngine 构建一个仅含给定自定义规则的过滤引擎
func rewriteTestEngine(t *testing.T, rules ...string) *core.RuleEngine {
	t.Helper()
	engine := core.NewRuleEngine(core.FilterConfig{
		Enabled:      true,
		BlockMode:    core.BlockModeNullIP,
		BlockingIPv4: core.DefaultBlockingIPv4,
		BlockingIPv6: core.DefaultBlockingIPv6,
		DataDir:      t.TempDir(),
		CustomRules:  rules,
		Lists:        []core.FilterList{},
	})
	t.Cleanup(engine.Close)
	return engine
}

func TestFilterMiddleware_DNSRewriteAnswersLocally(t *testing.T) {
	engine := rewriteTestEngine(t, "||internal.test^$dnsrewrite=10.0.0.5")
	mw := NewFilterMiddleware(engine)

	ctx := bogusCtx("internal.test")
	upstreamCalled := false
	if err := mw(ctx, nextCalled(&upstreamCalled)); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if upstreamCalled {
		t.Fatal("重写命中必须短路，不得走向上游")
	}
	if ctx.Resp == nil || ctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("unexpected response: %v", ctx.Resp)
	}
	if len(ctx.Resp.Answer) != 1 {
		t.Fatalf("answer count = %d, want 1", len(ctx.Resp.Answer))
	}
	a, ok := ctx.Resp.Answer[0].(*dns.A)
	if !ok || !a.A.Equal(net.ParseIP("10.0.0.5")) {
		t.Fatalf("unexpected answer: %v", ctx.Resp.Answer[0])
	}
	if src, _ := ctx.Get("source"); src != "dnsrewrite" {
		t.Fatalf("source = %v, want dnsrewrite", src)
	}
	// 重写不是拦截：标记为 false，避免查询日志把它统计成被拦截
	if v, _ := ctx.Get("filter_blocked"); v != false {
		t.Fatalf("filter_blocked = %v, want false", v)
	}
	if v, _ := ctx.Get("filter_action"); v != "rewrite" {
		t.Fatalf("filter_action = %v, want rewrite", v)
	}
}

func TestFilterMiddleware_DNSRewriteRefusedCode(t *testing.T) {
	engine := rewriteTestEngine(t, "||blocked.test^$dnsrewrite=REFUSED")
	mw := NewFilterMiddleware(engine)

	ctx := bogusCtx("blocked.test")
	if err := mw(ctx, nextCalled(new(bool))); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeRefused {
		t.Fatalf("rcode = %d, want REFUSED", ctx.Resp.Rcode)
	}
	if len(ctx.Resp.Answer) != 0 {
		t.Fatal("REFUSED 应答不应携带记录")
	}
}

// 未命中规则的查询必须原样放行，确保新增的 Tier 0 判定不影响既有行为
func TestFilterMiddleware_DNSRewriteMissesPassThrough(t *testing.T) {
	engine := rewriteTestEngine(t, "||internal.test^$dnsrewrite=10.0.0.5")
	mw := NewFilterMiddleware(engine)

	ctx := bogusCtx("other.test")
	called := false
	if err := mw(ctx, nextCalled(&called)); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("未命中重写必须继续传递")
	}
	if ctx.Resp != nil {
		t.Fatal("未命中重写不应构造应答")
	}
}

// 重写命中早于黑名单拦截：同一域名同时命中两者时返回重写结果
func TestFilterMiddleware_DNSRewritePrecedesBlock(t *testing.T) {
	engine := rewriteTestEngine(t, "||both.test^", "||both.test^$dnsrewrite=10.0.0.5")
	mw := NewFilterMiddleware(engine)

	ctx := bogusCtx("both.test")
	if err := mw(ctx, nextCalled(new(bool))); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(ctx.Resp.Answer) != 1 {
		t.Fatalf("expected the rewrite answer, got %v", ctx.Resp)
	}
	if a, ok := ctx.Resp.Answer[0].(*dns.A); !ok || !a.A.Equal(net.ParseIP("10.0.0.5")) {
		t.Fatalf("unexpected answer: %v", ctx.Resp.Answer[0])
	}
}

// 重写命中后 EDE 不应给出「被拦截」说明
func TestFilterMiddleware_DNSRewriteNoBlockedEDE(t *testing.T) {
	engine := rewriteTestEngine(t, "||internal.test^$dnsrewrite=10.0.0.5")

	req := new(dns.Msg)
	req.SetQuestion("internal.test.", dns.TypeA)
	req.SetEdns0(4096, false)
	ctx := NewDNSContext(context.Background(), req, nil, "udp")

	pipeline := NewPipeline(NewEDEMiddleware(true), NewFilterMiddleware(engine))
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("pipeline: %v", err)
	}
	if ede := GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp); ede != nil {
		t.Fatalf("重写应答不应携带 EDE 说明，得到 code=%d", ede.InfoCode)
	}
}
