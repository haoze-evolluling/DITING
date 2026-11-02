package dns

import (
	"context"
	"strings"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestHostsMiddleware_HitAndPass(t *testing.T) {
	hr, _ := core.NewHostsResolver(core.HostsConfig{Enabled: false})
	hr.LoadReader(strings.NewReader("10.0.0.5 router.lan\n"))

	mw := NewHostsMiddleware(hr)

	// Hit case
	req := new(dns.Msg)
	req.SetQuestion("router.lan.", dns.TypeA)
	ctx := &DNSContext{Context: context.Background(), Req: req}

	err := mw(ctx, func() error {
		t.Fatal("should not call next on hosts hit")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer from hosts middleware, got %v", ctx.Resp)
	}

	// Miss case
	reqMiss := new(dns.Msg)
	reqMiss.SetQuestion("google.com.", dns.TypeA)
	ctxMiss := &DNSContext{Context: context.Background(), Req: reqMiss}

	calledNext := false
	err = mw(ctxMiss, func() error {
		calledNext = true
		return nil
	})
	if err != nil || !calledNext {
		t.Fatalf("expected next to be called on miss, err=%v, calledNext=%v", err, calledNext)
	}

	// NODATA case: router.lan 仅有 A 记录，查询 AAAA 时权威返回 NODATA 且不转发上游
	reqAAAA := new(dns.Msg)
	reqAAAA.SetQuestion("router.lan.", dns.TypeAAAA)
	ctxAAAA := &DNSContext{Context: context.Background(), Req: reqAAAA}

	err = mw(ctxAAAA, func() error {
		t.Fatal("should not forward to next resolver when domain is locally owned in hosts")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error on NODATA query: %v", err)
	}
	if ctxAAAA.Resp == nil || ctxAAAA.Resp.Rcode != dns.RcodeSuccess || len(ctxAAAA.Resp.Answer) != 0 {
		t.Fatalf("expected authoritative NODATA (NOERROR, 0 answers), got %v", ctxAAAA.Resp)
	}
}
