package dns

import (
	"context"
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestUnqualifiedMiddleware_BlockUnqualified(t *testing.T) {
	mw := NewUnqualifiedMiddleware(true)

	// 1. 单标签域名如 "wpad." 应当被阻断为 NXDOMAIN
	req1 := new(dns.Msg)
	req1.SetQuestion("wpad.", dns.TypeA)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	called1 := false
	err1 := mw(ctx1, func() error {
		called1 = true
		return nil
	})
	if err1 != nil || called1 {
		t.Fatalf("expected unqualified query NOT to proceed to next")
	}
	if ctx1.Resp == nil || ctx1.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("expected NXDOMAIN for unqualified domain, got %v", ctx1.Resp)
	}
	if !ctx1.Resp.Authoritative {
		t.Fatalf("expected response to be authoritative")
	}

	// 2. 正常多标签 FQDN 域名如 "example.com." 应当放行
	req2 := new(dns.Msg)
	req2.SetQuestion("example.com.", dns.TypeA)
	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	called2 := false
	err2 := mw(ctx2, func() error {
		called2 = true
		return nil
	})
	if err2 != nil || !called2 {
		t.Fatalf("expected valid FQDN to call next")
	}

	// 3. 根域名 "." 应当放行
	req3 := new(dns.Msg)
	req3.SetQuestion(".", dns.TypeNS)
	ctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	called3 := false
	err3 := mw(ctx3, func() error {
		called3 = true
		return nil
	})
	if err3 != nil || !called3 {
		t.Fatalf("expected root domain query to call next")
	}
}

func TestUnqualifiedMiddleware_Disabled(t *testing.T) {
	mw := NewUnqualifiedMiddleware(false)

	req := new(dns.Msg)
	req.SetQuestion("laptop.", dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	called := false
	err := mw(ctx, func() error {
		called = true
		return nil
	})
	if err != nil || !called {
		t.Fatalf("expected query to pass when disabled")
	}
}

func TestUnqualifiedMiddleware_DynamicToggle(t *testing.T) {
	enabled := false
	mw := NewDynamicUnqualifiedMiddleware(func() bool { return enabled })

	req := new(dns.Msg)
	req.SetQuestion("printer.", dns.TypeA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	// 初始关闭：应放行
	called := false
	_ = mw(ctx, func() error {
		called = true
		return nil
	})
	if !called {
		t.Fatal("expected query to pass when initially false")
	}

	// 动态开启：应拦截
	enabled = true
	ctx2 := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	called2 := false
	_ = mw(ctx2, func() error {
		called2 = true
		return nil
	})
	if called2 || ctx2.Resp == nil || ctx2.Resp.Rcode != dns.RcodeNameError {
		t.Fatal("expected query to be blocked after dynamic toggle to true")
	}
}

