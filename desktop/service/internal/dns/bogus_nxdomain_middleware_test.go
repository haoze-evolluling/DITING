package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// bogusCtx 构造一次 A 查询的上下文
func bogusCtx(domain string) *DNSContext {
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	return NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("192.168.1.5"), Port: 5}, "udp")
}

// aReply 构造一条 A 记录应答
func aReply(req *dns.Msg, ips ...string) *dns.Msg {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Rcode = dns.RcodeSuccess
	for _, ip := range ips {
		resp.Answer = append(resp.Answer, &dns.A{
			Hdr: dns.RR_Header{Name: req.Question[0].Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
			A:   net.ParseIP(ip).To4(),
		})
	}
	return resp
}

func bogusMatcher(t *testing.T, entries ...string) func() *core.BogusNXDomainMatcher {
	t.Helper()
	m, _ := core.NewBogusNXDomainMatcher(entries)
	return func() *core.BogusNXDomainMatcher { return m }
}

func TestBogusMiddleware_RewritesHijackedAnswer(t *testing.T) {
	ctx := bogusCtx("ads.example")
	mw := NewBogusNXDomainMiddleware(bogusMatcher(t, "203.0.113.7"))

	err := mw(ctx, func() error {
		ctx.Resp = aReply(ctx.Req, "203.0.113.7")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("rcode = %d, want NXDOMAIN", ctx.Resp.Rcode)
	}
	if len(ctx.Resp.Answer) != 0 {
		t.Fatalf("the hijacked answer must be dropped, got %d records", len(ctx.Resp.Answer))
	}

	// 打上与规则拦截一致的标记，使 EDE 与查询日志无需为这条路径单开分支
	if v, _ := ctx.Get("bogus_nxdomain"); v != true {
		t.Error("bogus_nxdomain marker missing")
	}
	if v, _ := ctx.Get("filter_blocked"); v != true {
		t.Error("filter_blocked marker missing")
	}
	if v, _ := ctx.Get("filter_list"); v != "bogus-nxdomain" {
		t.Errorf("filter_list = %v, want bogus-nxdomain", v)
	}
	if v, ok := ctx.Get("filter_reason"); !ok {
		t.Error("filter_reason must explain what happened")
	} else if s, _ := v.(string); s == "" {
		t.Error("filter_reason must not be empty")
	}
}

func TestBogusMiddleware_PassesThroughCleanAnswer(t *testing.T) {
	ctx := bogusCtx("good.example")
	mw := NewBogusNXDomainMiddleware(bogusMatcher(t, "203.0.113.7"))

	err := mw(ctx, func() error {
		ctx.Resp = aReply(ctx.Req, "93.184.216.34")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeSuccess || len(ctx.Resp.Answer) != 1 {
		t.Fatal("a clean answer must pass through untouched")
	}
	if _, ok := ctx.Get("bogus_nxdomain"); ok {
		t.Fatal("no marker should be set for a clean answer")
	}
}

// 只处理成功应答：把网络故障改写成"域名不存在"会掩盖真实原因
func TestBogusMiddleware_SkipsErrorResponses(t *testing.T) {
	for _, rcode := range []int{dns.RcodeServerFailure, dns.RcodeRefused} {
		ctx := bogusCtx("fail.example")
		mw := NewBogusNXDomainMiddleware(bogusMatcher(t, "0.0.0.0/8"))

		err := mw(ctx, func() error {
			resp := new(dns.Msg)
			resp.SetReply(ctx.Req)
			resp.Rcode = rcode
			// 即便挟带了可疑地址，错误应答也不该被改写
			resp.Answer = append(resp.Answer, &dns.A{
				Hdr: dns.RR_Header{Name: ctx.Req.Question[0].Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
				A:   net.IPv4zero.To4(),
			})
			ctx.Resp = resp
			return nil
		})
		if err != nil {
			t.Fatalf("rcode %d: unexpected error: %v", rcode, err)
		}
		if ctx.Resp.Rcode != rcode {
			t.Fatalf("rcode %d was rewritten to %d", rcode, ctx.Resp.Rcode)
		}
	}
}

// 已被其它中间件判定为拦截的应答保留其结论，避免归因被覆盖
func TestBogusMiddleware_SkipsAlreadyBlocked(t *testing.T) {
	ctx := bogusCtx("blocked.example")
	ctx.Set("filter_blocked", true)
	ctx.Set("filter_reason", "原有拦截原因")
	mw := NewBogusNXDomainMiddleware(bogusMatcher(t, "203.0.113.7"))

	err := mw(ctx, func() error {
		ctx.Resp = aReply(ctx.Req, "203.0.113.7")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode == dns.RcodeNameError {
		t.Fatal("an already-blocked answer must not be rewritten again")
	}
	if v, _ := ctx.Get("filter_reason"); v != "原有拦截原因" {
		t.Fatalf("the original reason must be preserved, got %v", v)
	}
}

// 未启用（matcher 返回 nil 或空清单）时必须是纯粹的透传，热路径零开销
func TestBogusMiddleware_NilMatcherIsNoOp(t *testing.T) {
	ctx := bogusCtx("any.example")
	mw := NewBogusNXDomainMiddleware(func() *core.BogusNXDomainMatcher { return nil })

	err := mw(ctx, func() error {
		ctx.Resp = aReply(ctx.Req, "0.0.0.0")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeSuccess || len(ctx.Resp.Answer) != 1 {
		t.Fatal("a nil matcher must not touch the answer")
	}

	empty := bogusCtx("any.example")
	mwEmpty := NewBogusNXDomainMiddleware(bogusMatcher(t))
	_ = mwEmpty(empty, func() error {
		empty.Resp = aReply(empty.Req, "0.0.0.0")
		return nil
	})
	if empty.Resp.Rcode != dns.RcodeSuccess {
		t.Fatal("an empty matcher must not touch the answer")
	}
}

// nil 工厂本身也必须安全（filterEngine 未就绪时的取值路径）
func TestBogusMiddleware_NilFactoryIsNoOp(t *testing.T) {
	ctx := bogusCtx("any.example")
	mw := NewBogusNXDomainMiddleware(nil)

	err := mw(ctx, func() error {
		ctx.Resp = aReply(ctx.Req, "0.0.0.0")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatal("a nil factory must not touch the answer")
	}
}

// 下层错误必须原样透传：纠正逻辑是响应侧增强，不应吞掉链路故障
func TestBogusMiddleware_PropagatesNextError(t *testing.T) {
	ctx := bogusCtx("err.example")
	mw := NewBogusNXDomainMiddleware(bogusMatcher(t, "203.0.113.7"))

	want := context.Canceled
	err := mw(ctx, func() error { return want })
	if err != want {
		t.Fatalf("err = %v, want %v", err, want)
	}
}

// 中间件通过工厂每次取最新匹配器，配置热更新后立即生效
func TestBogusMiddleware_FactoryHotReload(t *testing.T) {
	var current *core.BogusNXDomainMatcher
	mw := NewBogusNXDomainMiddleware(func() *core.BogusNXDomainMatcher { return current })

	ctx := bogusCtx("hot.example")
	_ = mw(ctx, func() error {
		ctx.Resp = aReply(ctx.Req, "203.0.113.7")
		return nil
	})
	if ctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatal("no matcher yet: the answer must pass through")
	}

	current, _ = core.NewBogusNXDomainMatcher([]string{"203.0.113.7"})
	ctx2 := bogusCtx("hot.example")
	_ = mw(ctx2, func() error {
		ctx2.Resp = aReply(ctx2.Req, "203.0.113.7")
		return nil
	})
	if ctx2.Resp.Rcode != dns.RcodeNameError {
		t.Fatal("a newly installed matcher must take effect immediately")
	}
}

// 完整管道：伪应答经缓存后被纠正，纠正结果本身也可被缓存
func TestBogusMiddleware_InPipelineWithCache(t *testing.T) {
	cache := core.NewDNSCache(core.DefaultCacheConfig())
	defer cache.Close()

	matcher, _ := core.NewBogusNXDomainMatcher([]string{"203.0.113.7"})
	upstreamCalls := 0

	pipeline := NewPipeline(
		NewCacheMiddleware(cache, nil),
		NewBogusNXDomainMiddleware(func() *core.BogusNXDomainMatcher { return matcher }),
		func(ctx *DNSContext, next func() error) error {
			upstreamCalls++
			ctx.Resp = aReply(ctx.Req, "203.0.113.7")
			return nil
		},
	)

	ctx := bogusCtx("hijacked.example")
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("pipeline: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("rcode = %d, want NXDOMAIN", ctx.Resp.Rcode)
	}
	if upstreamCalls != 1 {
		t.Fatalf("upstream calls = %d, want 1", upstreamCalls)
	}

	// 第二次查询应命中缓存，且缓存里存的必须是纠正后的 NXDOMAIN 而非伪地址
	ctx2 := bogusCtx("hijacked.example")
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("pipeline (cached): %v", err)
	}
	if upstreamCalls != 1 {
		t.Fatalf("the corrected answer must be served from cache, upstream calls = %d", upstreamCalls)
	}
	if ctx2.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("cached rcode = %d, want NXDOMAIN", ctx2.Resp.Rcode)
	}
	if len(ctx2.Resp.Answer) != 0 {
		t.Fatal("the cached answer must not carry the hijacked address")
	}
}
