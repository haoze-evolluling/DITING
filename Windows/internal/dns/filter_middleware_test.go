package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/miekg/dns"
)

func TestFilterMiddlewareBlockedNullIP(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := core.DefaultFilterConfig()
	cfg.DataDir = tmpDir
	cfg.Lists = []core.FilterList{}
	cfg.CustomRules = []string{
		"||ad.tracker.com^",
	}
	engine := core.NewRuleEngine(cfg)
	defer engine.Close()

	mw := NewFilterMiddleware(engine)

	// 1. 测试 IPv4 A 记录阻断
	reqA := new(dns.Msg)
	reqA.SetQuestion("ad.tracker.com.", dns.TypeA)
	ctxA := NewDNSContext(context.Background(), reqA, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	nextCalled := false
	err := mw(ctxA, func() error {
		nextCalled = true
		return nil
	})

	if err != nil {
		t.Fatalf("Middleware returned error: %v", err)
	}
	if nextCalled {
		t.Fatalf("next() should NOT be called for blocked query")
	}
	if ctxA.Resp == nil {
		t.Fatalf("Expected non-nil response for blocked query")
	}
	if len(ctxA.Resp.Answer) != 1 {
		t.Fatalf("Expected 1 answer RR, got %d", len(ctxA.Resp.Answer))
	}
	aRecord, ok := ctxA.Resp.Answer[0].(*dns.A)
	if !ok || aRecord.A.String() != "0.0.0.0" {
		t.Fatalf("Expected 0.0.0.0, got %v", ctxA.Resp.Answer[0])
	}
	if val, _ := ctxA.Get("filter_blocked"); val != true {
		t.Fatalf("Expected filter_blocked = true")
	}

	// 2. 测试 IPv6 AAAA 记录阻断
	reqAAAA := new(dns.Msg)
	reqAAAA.SetQuestion("ad.tracker.com.", dns.TypeAAAA)
	ctxAAAA := NewDNSContext(context.Background(), reqAAAA, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	err = mw(ctxAAAA, func() error {
		t.Fatalf("next() should NOT be called for blocked query")
		return nil
	})
	if err != nil {
		t.Fatalf("Middleware returned error: %v", err)
	}
	if len(ctxAAAA.Resp.Answer) != 1 {
		t.Fatalf("Expected 1 AAAA answer RR, got %d", len(ctxAAAA.Resp.Answer))
	}
	aaaaRecord, ok := ctxAAAA.Resp.Answer[0].(*dns.AAAA)
	if !ok || aaaaRecord.AAAA.String() != "::" {
		t.Fatalf("Expected ::, got %v", ctxAAAA.Resp.Answer[0])
	}
}

func TestFilterMiddlewareBlockModes(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := core.DefaultFilterConfig()
	cfg.DataDir = tmpDir
	cfg.Lists = []core.FilterList{}
	cfg.BlockMode = core.BlockModeNXDOMAIN
	cfg.CustomRules = []string{"||nx.blocked.com^"}

	engine := core.NewRuleEngine(cfg)
	defer engine.Close()

	mw := NewFilterMiddleware(engine)

	req := new(dns.Msg)
	req.SetQuestion("nx.blocked.com.", dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	err := mw(ctx, func() error {
		t.Fatalf("next() should not be called")
		return nil
	})
	if err != nil {
		t.Fatalf("Error: %v", err)
	}
	if ctx.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("Expected NXDOMAIN rcode, got %d", ctx.Resp.Rcode)
	}
}

func TestFilterMiddlewareWhitelistAndPass(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := core.DefaultFilterConfig()
	cfg.DataDir = tmpDir
	cfg.Lists = []core.FilterList{}
	cfg.CustomRules = []string{
		"||ad.com^",
		"@@||white.ad.com^",
	}

	engine := core.NewRuleEngine(cfg)
	defer engine.Close()

	mw := NewFilterMiddleware(engine)

	// 白名单放行
	reqWhite := new(dns.Msg)
	reqWhite.SetQuestion("white.ad.com.", dns.TypeA)
	ctxWhite := NewDNSContext(context.Background(), reqWhite, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	whiteNextCalled := false
	_ = mw(ctxWhite, func() error {
		whiteNextCalled = true
		return nil
	})
	if !whiteNextCalled {
		t.Fatalf("next() should be called for whitelisted domain")
	}
	if val, _ := ctxWhite.Get("filter_action"); val != "allow" {
		t.Fatalf("Expected filter_action = allow, got %v", val)
	}

	// 干净域名透传
	reqClean := new(dns.Msg)
	reqClean.SetQuestion("clean.com.", dns.TypeA)
	ctxClean := NewDNSContext(context.Background(), reqClean, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	cleanNextCalled := false
	_ = mw(ctxClean, func() error {
		cleanNextCalled = true
		return nil
	})
	if !cleanNextCalled {
		t.Fatalf("next() should be called for clean domain")
	}
}

func TestFilterMiddlewareDisabled(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := core.DefaultFilterConfig()
	cfg.Enabled = false
	cfg.DataDir = tmpDir
	cfg.Lists = []core.FilterList{}
	cfg.CustomRules = []string{"||blocked.com^"}

	engine := core.NewRuleEngine(cfg)
	defer engine.Close()

	mw := NewFilterMiddleware(engine)

	req := new(dns.Msg)
	req.SetQuestion("blocked.com.", dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 54321}, "udp")

	nextCalled := false
	_ = mw(ctx, func() error {
		nextCalled = true
		return nil
	})
	if !nextCalled {
		t.Fatalf("next() should be called when filtering is disabled")
	}
}
