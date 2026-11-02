package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestAccessMiddleware_AllowedAndBlocked(t *testing.T) {
	ac, err := core.NewAccessControl(core.AccessControlConfig{
		AllowedClients: []string{"192.168.1.0/24"},
		BlockedClients: []string{"192.168.1.99"},
	})
	if err != nil {
		t.Fatalf("failed to init access control: %v", err)
	}

	mw := NewAccessMiddleware(ac)

	// 1. 允许的客户端
	req1 := new(dns.Msg)
	req1.SetQuestion("example.com.", dns.TypeA)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("192.168.1.10"), Port: 12345}, "udp")

	called1 := false
	err1 := mw(ctx1, func() error {
		called1 = true
		ctx1.Resp = new(dns.Msg)
		ctx1.Resp.SetReply(req1)
		return nil
	})
	if err1 != nil || !called1 {
		t.Fatalf("expected next to be called for allowed client, got err=%v called=%v", err1, called1)
	}

	// 2. 显式阻断的客户端
	req2 := new(dns.Msg)
	req2.SetQuestion("example.com.", dns.TypeA)
	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("192.168.1.99"), Port: 12345}, "udp")

	called2 := false
	err2 := mw(ctx2, func() error {
		called2 = true
		return nil
	})
	if err2 != nil || called2 {
		t.Fatalf("expected next NOT to be called for blocked client")
	}
	if ctx2.Resp == nil || ctx2.Resp.Rcode != dns.RcodeRefused {
		t.Fatalf("expected REFUSED rcode, got %v", ctx2.Resp)
	}
	if val, ok := ctx2.Get("access_blocked"); !ok || val != true {
		t.Fatalf("expected access_blocked attribute to be set")
	}

	// 3. 不在白名单网段内的外来客户端
	req3 := new(dns.Msg)
	req3.SetQuestion("example.com.", dns.TypeA)
	ctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("10.0.0.1"), Port: 12345}, "udp")

	called3 := false
	err3 := mw(ctx3, func() error {
		called3 = true
		return nil
	})
	if err3 != nil || called3 {
		t.Fatalf("expected next NOT to be called for unallowed client")
	}
	if ctx3.Resp == nil || ctx3.Resp.Rcode != dns.RcodeRefused {
		t.Fatalf("expected REFUSED rcode, got %v", ctx3.Resp)
	}
}
