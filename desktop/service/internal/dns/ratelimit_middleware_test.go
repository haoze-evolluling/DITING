package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestRateLimitMiddleware(t *testing.T) {
	cfg := core.RateLimitConfig{
		Enabled:    true,
		Rate:       1.0,
		Burst:      2,
		IPv4Prefix: 32,
		IPv6Prefix: 128,
		ExemptIPs:  []string{"127.0.0.1"},
	}

	limiter, err := core.NewRateLimiter(context.Background(), cfg)
	if err != nil {
		t.Fatalf("NewRateLimiter: %v", err)
	}
	defer limiter.Close()

	mw := NewRateLimitMiddleware(limiter)

	clientAddr := &net.UDPAddr{IP: net.ParseIP("192.168.1.150"), Port: 5353}
	req := new(dns.Msg)
	req.SetQuestion("test.example.com.", dns.TypeA)

	// 前 2 次应当允许
	for i := 0; i < 2; i++ {
		ctx := NewDNSContext(context.Background(), req, clientAddr, "udp")
		called := false
		err := mw(ctx, func() error {
			called = true
			return nil
		})
		if err != nil || !called {
			t.Fatalf("request %d should have passed, err=%v called=%v", i+1, err, called)
		}
	}

	// 第 3 次应当被限流
	ctxLimit := NewDNSContext(context.Background(), req, clientAddr, "udp")
	calledLimit := false
	errLimit := mw(ctxLimit, func() error {
		calledLimit = true
		return nil
	})
	if errLimit != nil || calledLimit {
		t.Fatalf("request 3 should have been intercepted by rate limiter")
	}
	if ctxLimit.Resp == nil || ctxLimit.Resp.Rcode != dns.RcodeRefused {
		t.Fatalf("expected REFUSED response, got %v", ctxLimit.Resp)
	}
	if val, ok := ctxLimit.Get("ratelimit_blocked"); !ok || val != true {
		t.Fatalf("expected ratelimit_blocked attribute")
	}

	// 豁免的 127.0.0.1 应当放行
	exemptAddr := &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}
	ctxExempt := NewDNSContext(context.Background(), req, exemptAddr, "udp")
	calledExempt := false
	errExempt := mw(ctxExempt, func() error {
		calledExempt = true
		return nil
	})
	if errExempt != nil || !calledExempt {
		t.Fatalf("exempt client should pass, err=%v called=%v", errExempt, calledExempt)
	}
}
