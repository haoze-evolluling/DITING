package dns

import (
	"context"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func newZoneTestEngine(t *testing.T, content string) *core.ZoneEngine {
	t.Helper()
	engine := core.NewZoneEngine(core.ZoneConfig{
		Enabled: true,
		TTL:     300,
		Zones: []core.ZoneEntry{{
			ID:      "z1",
			Origin:  "lan",
			Enabled: true,
			Content: content,
		}},
	})
	return engine
}

func runZoneMw(t *testing.T, engine *core.ZoneEngine, name string, qtype uint16) (*DNSContext, bool) {
	t.Helper()
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(name), qtype)
	ctx := NewDNSContext(context.Background(), req, nil, "udp")

	reached := false
	mw := NewZoneMiddleware(engine)
	err := mw(ctx, func() error {
		reached = true
		return nil
	})
	if err != nil {
		t.Fatalf("中间件返回错误: %v", err)
	}
	return ctx, reached
}

func TestZoneMiddleware_AnswersAuthoritatively(t *testing.T) {
	engine := newZoneTestEngine(t, `$ORIGIN lan.
@   IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)
www IN A   10.0.0.10
www IN A   10.0.0.11
`)

	ctx, reached := runZoneMw(t, engine, "www.lan", dns.TypeA)
	if reached {
		t.Fatal("命中权威区后不应继续向下传递")
	}
	if ctx.Resp == nil {
		t.Fatal("应构造应答")
	}
	if !ctx.Resp.Authoritative {
		t.Fatal("区应答必须带 AA 标志")
	}
	if ctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("应答码应为 NOERROR，实得 %d", ctx.Resp.Rcode)
	}
	if len(ctx.Resp.Answer) != 2 {
		t.Fatalf("期望 2 条 A 记录，实得 %d", len(ctx.Resp.Answer))
	}
	if src, _ := ctx.Get("source"); src != "zone" {
		t.Fatalf("来源标记应为 zone，实得 %v", src)
	}
	if hit, _ := ctx.Get("cache_hit"); hit != "zone" {
		t.Fatalf("缓存标记应为 zone，实得 %v", hit)
	}
}

// 区内存在但类型不匹配时必须短路为权威 NODATA（带 SOA），
// 放行到上游就等于把内网域名送出去
func TestZoneMiddleware_NodataShortCircuits(t *testing.T) {
	engine := newZoneTestEngine(t, `$ORIGIN lan.
@   IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)
www IN A   10.0.0.10
`)

	ctx, reached := runZoneMw(t, engine, "www.lan", dns.TypeAAAA)
	if reached {
		t.Fatal("区内名字的其它类型查询不应外泄到上游")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 0 {
		t.Fatalf("应为 NODATA 应答，实得 %+v", ctx.Resp)
	}
	if len(ctx.Resp.Ns) != 1 {
		t.Fatalf("NODATA 应附一条 SOA，实得 %d 条", len(ctx.Resp.Ns))
	}
	if _, ok := ctx.Resp.Ns[0].(*dns.SOA); !ok {
		t.Fatalf("附加记录应为 SOA，实得 %T", ctx.Resp.Ns[0])
	}
	if hit, _ := ctx.Get("cache_hit"); hit != "zone_nodata" {
		t.Fatalf("缓存标记应为 zone_nodata，实得 %v", hit)
	}
}

// 区里没写 SOA 时也要合成一条，否则 NODATA 无法被客户端负缓存
func TestZoneMiddleware_SynthesizesSOA(t *testing.T) {
	engine := newZoneTestEngine(t, "$ORIGIN lan.\nwww IN A 10.0.0.10\n")

	ctx, _ := runZoneMw(t, engine, "www.lan", dns.TypeMX)
	if ctx.Resp == nil || len(ctx.Resp.Ns) != 1 {
		t.Fatalf("缺 SOA 的区也应合成一条，实得 %+v", ctx.Resp)
	}
	soa, ok := ctx.Resp.Ns[0].(*dns.SOA)
	if !ok {
		t.Fatalf("附加记录应为 SOA，实得 %T", ctx.Resp.Ns[0])
	}
	if soa.Hdr.Name != "lan." {
		t.Fatalf("合成 SOA 的拥有者应为区顶点，实得 %q", soa.Hdr.Name)
	}
}

func TestZoneMiddleware_PassesThroughOutsideZone(t *testing.T) {
	engine := newZoneTestEngine(t, "$ORIGIN lan.\nwww IN A 10.0.0.10\n")

	ctx, reached := runZoneMw(t, engine, "example.com", dns.TypeA)
	if !reached {
		t.Fatal("区外查询应继续向下传递")
	}
	if ctx.Resp != nil {
		t.Fatal("区外查询不应产生本地应答")
	}
}

func TestZoneMiddleware_NilAndDisabledEngine(t *testing.T) {
	ctx, reached := runZoneMw(t, nil, "www.lan", dns.TypeA)
	if !reached || ctx.Resp != nil {
		t.Fatal("引擎为 nil 时应直接放行")
	}

	disabled := core.NewZoneEngine(core.ZoneConfig{
		Enabled: false,
		Zones:   []core.ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n"}},
	})
	if _, reached := runZoneMw(t, disabled, "www.lan", dns.TypeA); !reached {
		t.Fatal("全局关闭时应直接放行")
	}
}

func TestZoneMiddleware_EmptyQuestion(t *testing.T) {
	engine := newZoneTestEngine(t, "$ORIGIN lan.\nwww IN A 10.0.0.10\n")

	req := new(dns.Msg)
	ctx := NewDNSContext(context.Background(), req, nil, "udp")
	reached := false
	mw := NewZoneMiddleware(engine)
	if err := mw(ctx, func() error { reached = true; return nil }); err != nil {
		t.Fatalf("空问题区不应报错: %v", err)
	}
	if !reached {
		t.Fatal("空问题区应直接放行")
	}
}

func TestZoneMiddleware_PTRRecord(t *testing.T) {
	engine := newZoneTestEngine(t, `$ORIGIN lan.
@   IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)
1.0.0 IN PTR host1.lan.
`)

	ctx, reached := runZoneMw(t, engine, "1.0.0.lan", dns.TypePTR)
	if reached {
		t.Fatal("反向记录同样应由本地权威应答")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("期望 1 条 PTR，实得 %+v", ctx.Resp)
	}
	if _, ok := ctx.Resp.Answer[0].(*dns.PTR); !ok {
		t.Fatalf("记录类型应为 PTR，实得 %T", ctx.Resp.Answer[0])
	}
}

// 应答记录不应与索引共享对象：缓存与响应改写会就地修改记录
func TestZoneMiddleware_ResponseIsolatedFromIndex(t *testing.T) {
	engine := newZoneTestEngine(t, "$ORIGIN lan.\nwww IN A 10.0.0.10\n")

	ctx, _ := runZoneMw(t, engine, "www.lan", dns.TypeA)
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("首次查询异常: %+v", ctx.Resp)
	}
	ctx.Resp.Answer[0].Header().Ttl = 1

	again, _ := runZoneMw(t, engine, "www.lan", dns.TypeA)
	if again.Resp.Answer[0].Header().Ttl != 300 {
		t.Fatalf("索引被应答侧修改污染，TTL = %d", again.Resp.Answer[0].Header().Ttl)
	}
}
