package dns

import (
	"context"
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestSUDNMiddleware_Localhost(t *testing.T) {
	mw := NewSUDNMiddleware()

	// IPv4 query
	reqA := new(dns.Msg)
	reqA.SetQuestion("localhost.", dns.TypeA)
	ctxA := &DNSContext{Context: context.Background(), Req: reqA}

	err := mw(ctxA, func() error {
		t.Fatal("should short-circuit and not call next")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctxA.Resp == nil || len(ctxA.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer for localhost A, got %v", ctxA.Resp)
	}
	aRecord := ctxA.Resp.Answer[0].(*dns.A)
	if !aRecord.A.Equal(net.ParseIP("127.0.0.1")) {
		t.Fatalf("expected 127.0.0.1, got %v", aRecord.A)
	}

	// IPv6 query
	reqAAAA := new(dns.Msg)
	reqAAAA.SetQuestion("my.localhost.", dns.TypeAAAA)
	ctxAAAA := &DNSContext{Context: context.Background(), Req: reqAAAA}

	err = mw(ctxAAAA, func() error {
		t.Fatal("should short-circuit and not call next")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctxAAAA.Resp == nil || len(ctxAAAA.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer for localhost AAAA, got %v", ctxAAAA.Resp)
	}
	aaaaRecord := ctxAAAA.Resp.Answer[0].(*dns.AAAA)
	if !aaaaRecord.AAAA.Equal(net.IPv6loopback) {
		t.Fatalf("expected ::1, got %v", aaaaRecord.AAAA)
	}
}

func TestSUDNMiddleware_NXDomainZones(t *testing.T) {
	mw := NewSUDNMiddleware()

	zones := []string{"hidden.onion.", "something.invalid.", "test.", "sub.test.", "mydevice.home.arpa."}
	for _, z := range zones {
		req := new(dns.Msg)
		req.SetQuestion(z, dns.TypeA)
		ctx := &DNSContext{Context: context.Background(), Req: req}

		err := mw(ctx, func() error {
			t.Fatalf("should not call next for %s", z)
			return nil
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if ctx.Resp == nil || ctx.Resp.Rcode != dns.RcodeNameError {
			t.Fatalf("expected NXDOMAIN for %s, got rcode=%d", z, ctx.Resp.Rcode)
		}
	}
}

func TestSUDNMiddleware_DDR_ResolverArpa(t *testing.T) {
	mw := NewSUDNMiddleware()

	req := new(dns.Msg)
	req.SetQuestion("_dns.resolver.arpa.", dns.TypeSVCB)
	ctx := &DNSContext{Context: context.Background(), Req: req}

	err := mw(ctx, func() error {
		t.Fatal("should not call next for resolver.arpa")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp == nil || ctx.Resp.Rcode != dns.RcodeSuccess || len(ctx.Resp.Answer) != 0 {
		t.Fatalf("expected NODATA for resolver.arpa, got %v", ctx.Resp)
	}
}

func TestSUDNMiddleware_Passthrough(t *testing.T) {
	mw := NewSUDNMiddleware()

	req := new(dns.Msg)
	req.SetQuestion("example.com.", dns.TypeA)
	ctx := &DNSContext{Context: context.Background(), Req: req}

	calledNext := false
	err := mw(ctx, func() error {
		calledNext = true
		return nil
	})
	if err != nil || !calledNext {
		t.Fatalf("expected passthrough to next, got err=%v, calledNext=%v", err, calledNext)
	}
}
