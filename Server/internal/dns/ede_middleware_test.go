package dns

import (
	"context"
	"errors"
	"testing"

	"github.com/miekg/dns"
)

// 伪应答纠正走被拦截（Blocked）而非伪造应答（Forged Answer）：
// 纠正后的报文是 NXDOMAIN，并未替客户端"伪造"任何地址。
func TestEDEMiddleware_BogusNXDomain(t *testing.T) {
	mw := NewEDEMiddleware(true)
	req := new(dns.Msg)
	req.SetEdns0(4096, false)
	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    new(dns.Msg),
	}
	ctx.Set("bogus_nxdomain", true)
	// 同时被打上规则拦截标记（中间件如此设置），EDE 必须给出更具体的原因
	ctx.Set("filter_blocked", true)
	ctx.Set("filter_reason", "伪应答纠正: x.test. 解析为 0.0.0.0")

	err := mw(ctx, func() error { return nil })
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	ede := GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp)
	if ede == nil {
		t.Fatal("expected EDE option in response")
	}
	if ede.InfoCode != dns.ExtendedErrorCodeBlocked {
		t.Fatalf("expected code %d, got %d", dns.ExtendedErrorCodeBlocked, ede.InfoCode)
	}
}

func TestEDEMiddleware_BlockedByFilter(t *testing.T) {
	mw := NewEDEMiddleware(true)
	req := new(dns.Msg)
	req.SetEdns0(4096, false)
	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    new(dns.Msg),
	}
	ctx.Set("filter_blocked", true)
	ctx.Set("filter_reason", "Malware domain blocked")

	err := mw(ctx, func() error {
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	ede := GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp)
	if ede == nil {
		t.Fatal("expected EDE option in response")
	}
	if ede.InfoCode != dns.ExtendedErrorCodeBlocked {
		t.Fatalf("expected code %d, got %d", dns.ExtendedErrorCodeBlocked, ede.InfoCode)
	}
	if ede.ExtraText != "DITING: Malware domain blocked" {
		t.Fatalf("unexpected extra text: %s", ede.ExtraText)
	}
}

func TestEDEMiddleware_BlockedByRebind(t *testing.T) {
	mw := NewEDEMiddleware(true)
	req := new(dns.Msg)
	req.SetEdns0(4096, false)
	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    new(dns.Msg),
	}
	ctx.Set("rebinding_blocked", true)

	err := mw(ctx, func() error {
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	ede := GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp)
	if ede == nil {
		t.Fatal("expected EDE option in response")
	}
	if ede.InfoCode != dns.ExtendedErrorCodeProhibited {
		t.Fatalf("expected code %d, got %d", dns.ExtendedErrorCodeProhibited, ede.InfoCode)
	}
}

func TestEDEMiddleware_UpstreamFailure(t *testing.T) {
	mw := NewEDEMiddleware(true)
	req := new(dns.Msg)
	req.SetEdns0(4096, false)
	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    new(dns.Msg),
		Err:     errors.New("connection timeout"),
	}
	ctx.Resp.Rcode = dns.RcodeServerFailure

	_ = mw(ctx, func() error {
		return ctx.Err
	})

	ede := GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp)
	if ede == nil {
		t.Fatal("expected EDE option in response")
	}
	if ede.InfoCode != dns.ExtendedErrorCodeNetworkError {
		t.Fatalf("expected code %d, got %d", dns.ExtendedErrorCodeNetworkError, ede.InfoCode)
	}
}

func TestEDEMiddleware_NoClientEDNS0(t *testing.T) {
	// 验证 RFC 8914 Section 3: 客户端请求未提供 OPT RR 时，响应严禁附带 EDE
	mw := NewEDEMiddleware(true)
	req := new(dns.Msg) // 未调用 SetEdns0
	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    new(dns.Msg),
	}
	ctx.Set("filter_blocked", true)

	_ = mw(ctx, func() error { return nil })
	if GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp) != nil {
		t.Fatal("RFC 8914 violation: EDE option must not be attached when client request lacks EDNS0")
	}
}

func TestEDEMiddleware_Disabled(t *testing.T) {
	mw := NewEDEMiddleware(false)
	req := new(dns.Msg)
	req.SetEdns0(4096, false)
	ctx := &DNSContext{
		Context: context.Background(),
		Req:     req,
		Resp:    new(dns.Msg),
	}
	ctx.Set("filter_blocked", true)

	_ = mw(ctx, func() error { return nil })
	if GetEdns0Option[*dns.EDNS0_EDE](ctx.Resp) != nil {
		t.Fatal("expected no EDE option when disabled")
	}
}
