package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestRewriteMiddleware_Execution(t *testing.T) {
	engine := core.NewRewriteEngine(core.RewriteConfig{
		Enabled: true,
		TTL:     60,
		Rules: []core.RewriteRule{
			{Domain: "dev.lan", IPs: []string{"192.168.1.200"}},
			{Domain: "*.cloud.local", IPs: []string{"10.0.0.1"}},
		},
	})

	mw := NewRewriteMiddleware(engine)

	// 1. 命中 dev.lan
	req := new(dns.Msg)
	req.SetQuestion("dev.lan.", dns.TypeA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 12345}, "udp")

	calledNext := false
	err := mw(dctx, func() error {
		calledNext = true
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calledNext {
		t.Fatalf("expected next not to be called for matched rewrite rule")
	}
	if dctx.Resp == nil || len(dctx.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer record, got %v", dctx.Resp)
	}
	aRec := dctx.Resp.Answer[0].(*dns.A)
	if !aRec.A.Equal(net.ParseIP("192.168.1.200")) {
		t.Fatalf("ip mismatch: %v", aRec.A)
	}
	if hit, _ := dctx.Get("cache_hit"); hit != "rewrite" {
		t.Fatalf("expected cache_hit rewrite, got %v", hit)
	}

	// 2. 命中泛域名 *.cloud.local
	req = new(dns.Msg)
	req.SetQuestion("api.cloud.local.", dns.TypeA)
	dctx = NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 12345}, "udp")

	calledNext = false
	err = mw(dctx, func() error {
		calledNext = true
		return nil
	})
	if err != nil || calledNext {
		t.Fatalf("wildcard rewrite should intercept before next")
	}
	if len(dctx.Resp.Answer) != 1 {
		t.Fatalf("expected 1 wildcard answer")
	}

	// 3. 命中权威 NODATA (dev.lan 请求 AAAA)
	req = new(dns.Msg)
	req.SetQuestion("dev.lan.", dns.TypeAAAA)
	dctx = NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 12345}, "udp")

	calledNext = false
	err = mw(dctx, func() error {
		calledNext = true
		return nil
	})
	if err != nil || calledNext {
		t.Fatalf("nodata rewrite should intercept before next")
	}
	if dctx.Resp == nil || dctx.Resp.Rcode != dns.RcodeSuccess || len(dctx.Resp.Answer) != 0 {
		t.Fatalf("expected authoritative NODATA with empty answer, got: %v", dctx.Resp)
	}
	if hit, _ := dctx.Get("cache_hit"); hit != "rewrite_nodata" {
		t.Fatalf("expected cache_hit rewrite_nodata, got %v", hit)
	}

	// 4. 未匹配域名透传至 next
	req = new(dns.Msg)
	req.SetQuestion("unrelated.com.", dns.TypeA)
	dctx = NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 12345}, "udp")

	calledNext = false
	err = mw(dctx, func() error {
		calledNext = true
		return nil
	})
	if err != nil || !calledNext {
		t.Fatalf("unmatched domain should pass to next")
	}
}
