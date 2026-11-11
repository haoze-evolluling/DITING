package dns

import (
	"context"
	"net"
	"testing"

	"github.com/miekg/dns"
)

// anyCtx 构造一次任意类型的查询上下文
func anyCtx(qtype uint16, qclass uint16) *DNSContext {
	req := new(dns.Msg)
	req.SetQuestion("example.com.", qtype)
	req.Question[0].Qclass = qclass
	return NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("192.168.1.5"), Port: 5}, "udp")
}

// anyMiddleware 组装一个开关与模式固定的中间件
func anyMiddleware(enabled bool, mode string) Middleware {
	return NewANYMiddleware(func() bool { return enabled }, func() string { return mode })
}

// nextCalled 记录是否走到了下游，用于断言短路行为
func nextCalled(called *bool) func() error {
	return func() error {
		*called = true
		return nil
	}
}

func TestANYMiddleware_MinimizesANYQuery(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	called := false

	err := anyMiddleware(true, "notimp")(ctx, nextCalled(&called))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if called {
		t.Fatal("ANY 查询必须短路，不得继续走向上游")
	}
	if ctx.Resp == nil {
		t.Fatal("expected a synthetic response")
	}
	if ctx.Resp.Rcode != dns.RcodeNotImplemented {
		t.Fatalf("rcode = %d, want NOTIMP", ctx.Resp.Rcode)
	}
	if ctx.Resp.Id != ctx.Req.Id {
		t.Fatalf("response id = %d, want %d", ctx.Resp.Id, ctx.Req.Id)
	}
	if len(ctx.Resp.Answer) != 0 {
		t.Fatalf("NOTIMP 应答不应携带任何记录，got %d", len(ctx.Resp.Answer))
	}
}

func TestANYMiddleware_RFC8482Mode(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	called := false

	err := anyMiddleware(true, "rfc8482")(ctx, nextCalled(&called))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if called {
		t.Fatal("ANY 查询必须短路，不得继续走向上游")
	}
	if ctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("rcode = %d, want NOERROR", ctx.Resp.Rcode)
	}
	if len(ctx.Resp.Answer) != 1 {
		t.Fatalf("answer count = %d, want 1", len(ctx.Resp.Answer))
	}

	hinfo, ok := ctx.Resp.Answer[0].(*dns.HINFO)
	if !ok {
		t.Fatalf("answer type = %T, want *dns.HINFO", ctx.Resp.Answer[0])
	}
	if hinfo.Cpu != RFC8482HINFO {
		t.Fatalf("cpu = %q, want %q", hinfo.Cpu, RFC8482HINFO)
	}
	if hinfo.Hdr.Name != "example.com." {
		t.Fatalf("record name = %q, want the queried name", hinfo.Hdr.Name)
	}
	// TTL 必须为 0：这不是一条可缓存的事实，而是对查询形式本身的说明
	if hinfo.Hdr.Ttl != 0 {
		t.Fatalf("ttl = %d, want 0", hinfo.Hdr.Ttl)
	}
}

// 最小化只针对会外泄到上游的查询，其它类型必须原样放行
func TestANYMiddleware_OnlyMatchesANYType(t *testing.T) {
	for _, qtype := range []uint16{dns.TypeA, dns.TypeAAAA, dns.TypeHINFO, dns.TypeTXT} {
		t.Run(dns.TypeToString[qtype], func(t *testing.T) {
			ctx := anyCtx(qtype, dns.ClassINET)
			called := false

			if err := anyMiddleware(true, "notimp")(ctx, nextCalled(&called)); err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !called {
				t.Fatal("非 ANY 查询必须继续传递")
			}
			if ctx.Resp != nil {
				t.Fatal("非 ANY 查询不应被伪造应答")
			}
		})
	}
}

// CH 类查询（如版本探测）不属于放大攻击面，不能被最小化
func TestANYMiddleware_IgnoresNonINETClass(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassCHAOS)
	called := false

	if err := anyMiddleware(true, "notimp")(ctx, nextCalled(&called)); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("非 IN 类 ANY 查询必须继续传递")
	}
	if ctx.Resp != nil {
		t.Fatal("非 IN 类 ANY 查询不应被伪造应答")
	}
}

func TestANYMiddleware_DisabledPassesThrough(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	called := false

	if err := anyMiddleware(false, "notimp")(ctx, nextCalled(&called)); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("开关关闭时 ANY 查询必须继续传递")
	}
	if ctx.Resp != nil {
		t.Fatal("开关关闭时不应构造应答")
	}
}

func TestANYMiddleware_UnknownModeFallsBackToNotImp(t *testing.T) {
	for _, mode := range []string{"", "  ", "RFC8482-NOT", "bogus"} {
		t.Run(mode, func(t *testing.T) {
			ctx := anyCtx(dns.TypeANY, dns.ClassINET)
			if err := anyMiddleware(true, mode)(ctx, nextCalled(new(bool))); err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if ctx.Resp.Rcode != dns.RcodeNotImplemented {
				t.Fatalf("mode %q: rcode = %d, want NOTIMP", mode, ctx.Resp.Rcode)
			}
		})
	}
}

// 大小写与空白不应影响模式判定，配置热更新时前端可能回填不规范取值
func TestANYMiddleware_ModeIsCaseInsensitive(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	if err := anyMiddleware(true, "  RFC8482 ")(ctx, nextCalled(new(bool))); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("rcode = %d, want NOERROR", ctx.Resp.Rcode)
	}
}

// 打上与规则拦截一致的标记，使 EDE 与查询日志无需为这条路径单开分支
func TestANYMiddleware_MarksBlocked(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	if err := anyMiddleware(true, "notimp")(ctx, nextCalled(new(bool))); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if v, _ := ctx.Get("any_blocked"); v != true {
		t.Error("any_blocked marker missing")
	}
	if v, _ := ctx.Get("filter_blocked"); v != true {
		t.Error("filter_blocked marker missing")
	}
	if v, _ := ctx.Get("filter_rule"); v != "BLOCK_ANY" {
		t.Errorf("filter_rule = %v, want BLOCK_ANY", v)
	}
}

func TestANYMiddleware_NilEnabledFuncPassesThrough(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	called := false

	if err := NewANYMiddleware(nil, nil)(ctx, nextCalled(&called)); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("enabled 回调缺失时必须放行，而不是构造一个无人能关闭的应答")
	}
}

// EDE 必须在 ANY 最小化这条路径上给出可读原因（EDE 注册在 ANY 之前）
func TestANYMiddleware_EDEReportsMinimization(t *testing.T) {
	req := new(dns.Msg)
	req.SetQuestion("example.com.", dns.TypeANY)
	req.SetEdns0(4096, false)
	ctx := &DNSContext{Context: context.Background(), Req: req, Resp: new(dns.Msg)}

	pipeline := NewPipeline(NewEDEMiddleware(true), anyMiddleware(true, "notimp"))
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("pipeline: %v", err)
	}

	ede := GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp)
	if ede == nil {
		t.Fatal("expected EDE option in response")
	}
	if ede.InfoCode != dns.ExtendedErrorCodeBlocked {
		t.Fatalf("ede code = %d, want %d", ede.InfoCode, dns.ExtendedErrorCodeBlocked)
	}
}

// 注册在本地权威应答之后时，前序中间件已给出结论便不再调用 next，
// 因此 ANY 最小化根本不会执行——这正是它必须排在 hosts / rewrite 之后的原因。
func TestANYMiddleware_AfterLocalAuthority(t *testing.T) {
	ctx := anyCtx(dns.TypeANY, dns.ClassINET)
	anyMw := anyMiddleware(true, "notimp")

	localAnswer := func(c *DNSContext, _ func() error) error {
		resp := new(dns.Msg)
		resp.SetReply(c.Req)
		resp.Answer = append(resp.Answer, &dns.A{
			Hdr: dns.RR_Header{Name: "example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
			A:   net.ParseIP("10.0.0.1").To4(),
		})
		c.Resp = resp
		return nil
	}

	pipeline := NewPipeline(localAnswer, anyMw)
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("pipeline: %v", err)
	}
	// 前序中间件短路返回后，ANY 中间件仍会执行——它按约定只看 Req，
	// 因此必须自己确认"是否已有应答"，否则会覆盖本地权威结果。
	if ctx.Resp.Rcode == dns.RcodeNotImplemented {
		t.Fatal("ANY 最小化覆盖了前序中间件已给出的本地权威应答")
	}
}
