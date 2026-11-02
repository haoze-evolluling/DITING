package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestIsBlockedIP(t *testing.T) {
	tests := []struct {
		ip      string
		blocked bool
	}{
		{"127.0.0.1", true},
		{"10.0.0.1", true},
		{"172.16.0.1", true},
		{"192.168.1.1", true},
		{"169.254.1.1", true},
		{"::1", true},
		{"fe80::1", true},
		{"fc00::1", true},
		{"0.0.0.0", true},
		{"8.8.8.8", false},
		{"1.1.1.1", false},
		{"223.5.5.5", false},
		{"2606:4700:4700::1111", false},
	}

	for _, tt := range tests {
		ip := net.ParseIP(tt.ip)
		if got := IsBlockedIP(ip); got != tt.blocked {
			t.Errorf("IsBlockedIP(%s) = %v, want %v", tt.ip, got, tt.blocked)
		}
	}
}

func TestRebindMiddleware_Blocked(t *testing.T) {
	cfg := DefaultRebindConfig()
	mgr := NewRebindProtectionManager(cfg)
	mw := NewRebindMiddleware(mgr)

	req := new(dns.Msg)
	req.SetQuestion("evil-attacker.com.", dns.TypeA)

	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "evil-attacker.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
		A:   net.ParseIP("192.168.1.1"),
	})

	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    resp,
	}

	err := mw(ctx, func() error {
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	val, ok := ctx.Get("rebinding_blocked")
	if !ok || val != true {
		t.Fatal("expected rebinding_blocked to be true")
	}

	if len(ctx.Resp.Answer) != 0 {
		t.Fatalf("expected answers to be cleared, got %d answers", len(ctx.Resp.Answer))
	}
}

func TestRebindMiddleware_AllowedDomains(t *testing.T) {
	cfg := DefaultRebindConfig()
	mgr := NewRebindProtectionManager(cfg)
	mw := NewRebindMiddleware(mgr)

	// router.lan should be allowed because .lan is in allowed list
	req := new(dns.Msg)
	req.SetQuestion("router.lan.", dns.TypeA)

	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "router.lan.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
		A:   net.ParseIP("192.168.1.1"),
	})

	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    resp,
	}

	err := mw(ctx, func() error {
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if val, ok := ctx.Get("rebinding_blocked"); ok && val == true {
		t.Fatal("expected router.lan to be permitted")
	}
	if len(ctx.Resp.Answer) != 1 {
		t.Fatalf("expected answer preserved, got %d", len(ctx.Resp.Answer))
	}
}

func TestRebindMiddleware_PublicIPPassed(t *testing.T) {
	cfg := DefaultRebindConfig()
	mgr := NewRebindProtectionManager(cfg)
	mw := NewRebindMiddleware(mgr)

	req := new(dns.Msg)
	req.SetQuestion("google.com.", dns.TypeA)

	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "google.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
		A:   net.ParseIP("172.217.16.206"),
	})

	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    resp,
	}

	err := mw(ctx, func() error {
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if val, ok := ctx.Get("rebinding_blocked"); ok && val == true {
		t.Fatal("expected public IP to be allowed")
	}
}

func TestRebindMiddleware_CacheEvictionOnBlock(t *testing.T) {
	cache := core.NewDNSCache(core.DefaultCacheConfig())
	defer cache.Close()

	mgr := NewRebindProtectionManager(DefaultRebindConfig())
	mw := NewRebindMiddleware(mgr, cache)

	req := new(dns.Msg)
	req.SetQuestion("attacker.org.", dns.TypeA)

	// 先在缓存中写入恶意条目
	badResp := new(dns.Msg)
	badResp.SetReply(req)
	badResp.Answer = append(badResp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "attacker.org.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
		A:   net.ParseIP("10.0.0.1"),
	})
	cache.Put(req, badResp)

	// 确认缓存已写入
	if _, hit, _, _ := cache.Get(req); !hit {
		t.Fatal("expected cache hit prior to rebind test")
	}

	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    badResp.Copy(),
	}

	_ = mw(ctx, func() error { return nil })

	// 验证中间件阻断并剔除了缓存
	if val, ok := ctx.Get("rebinding_blocked"); !ok || val != true {
		t.Fatal("expected rebinding_blocked to be true")
	}
	if _, hit, _, _ := cache.Get(req); hit {
		t.Fatal("expected poisoned cache entry to be purged upon rebinding block")
	}
}
