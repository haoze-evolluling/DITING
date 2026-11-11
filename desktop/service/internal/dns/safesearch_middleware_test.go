package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// ssTestEngine 构造启用状态下仅开启 Google/Bing 的安全搜索引擎。
func ssTestEngine(t *testing.T) *core.SafeSearchEngine {
	t.Helper()
	cfg := core.DefaultSafeSearchConfig()
	cfg.Enabled = true
	return core.NewSafeSearchEngine(cfg)
}

func TestSafeSearchMiddleware_CNAMEAnswer(t *testing.T) {
	mw := NewSafeSearchMiddleware(ssTestEngine(t))

	req := new(dns.Msg)
	req.SetQuestion("www.google.com.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	calledNext := false
	if err := mw(dctx, func() error { calledNext = true; return nil }); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calledNext {
		t.Fatalf("命中安全搜索时应短路，不调用 next")
	}
	if dctx.Resp == nil || len(dctx.Resp.Answer) != 1 {
		t.Fatalf("应返回单条 CNAME 应答, 得到 %+v", dctx.Resp)
	}
	cname, ok := dctx.Resp.Answer[0].(*dns.CNAME)
	if !ok || cname.Target != "forcesafesearch.google.com." {
		t.Fatalf("CNAME 目标异常: %+v", dctx.Resp.Answer[0])
	}
	if src, _ := dctx.Get("source"); src != "safesearch" {
		t.Fatalf("source 应标注 safesearch, 得到 %v", src)
	}
	if hit, _ := dctx.Get("cache_hit"); hit != "safesearch" {
		t.Fatalf("cache_hit 应标注 safesearch, 得到 %v", hit)
	}
}

func TestSafeSearchMiddleware_IPAnswer(t *testing.T) {
	mw := NewSafeSearchMiddleware(ssTestEngine(t))

	req := new(dns.Msg)
	req.SetQuestion("yandex.ru.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	if err := mw(dctx, func() error { return nil }); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(dctx.Resp.Answer) != 1 {
		t.Fatalf("应返回单条 A 记录, 得到 %+v", dctx.Resp)
	}
	aRec, ok := dctx.Resp.Answer[0].(*dns.A)
	if !ok || !aRec.A.Equal(net.ParseIP("213.180.193.56")) {
		t.Fatalf("A 记录异常: %+v", dctx.Resp.Answer[0])
	}
}

func TestSafeSearchMiddleware_DisabledPassthrough(t *testing.T) {
	engine := core.NewSafeSearchEngine(core.DefaultSafeSearchConfig()) // 默认关闭
	mw := NewSafeSearchMiddleware(engine)

	req := new(dns.Msg)
	req.SetQuestion("www.google.com.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	calledNext := false
	if err := mw(dctx, func() error { calledNext = true; return nil }); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !calledNext || dctx.Resp != nil {
		t.Fatalf("关闭状态下应直接透传, next=%v resp=%v", calledNext, dctx.Resp)
	}
}

func TestSafeSearchMiddleware_NonMatchingDomain(t *testing.T) {
	mw := NewSafeSearchMiddleware(ssTestEngine(t))

	req := new(dns.Msg)
	req.SetQuestion("example.com.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	calledNext := false
	if err := mw(dctx, func() error { calledNext = true; return nil }); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !calledNext {
		t.Fatalf("未命中域名应透传")
	}
}

func TestSafeSearchMiddleware_NilEngine(t *testing.T) {
	mw := NewSafeSearchMiddleware(nil)
	req := new(dns.Msg)
	req.SetQuestion("www.google.com.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, nil, "udp")

	calledNext := false
	if err := mw(dctx, func() error { calledNext = true; return nil }); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !calledNext {
		t.Fatalf("nil 引擎应透传")
	}
}
