package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

type mockDNS64Resolver struct {
	aIP net.IP
}

func (m *mockDNS64Resolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	return nil, nil
}

func (m *mockDNS64Resolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	resp := new(dns.Msg)
	resp.SetReply(req)
	if len(req.Question) > 0 && req.Question[0].Qtype == dns.TypeA {
		resp.Answer = append(resp.Answer, &dns.A{
			Hdr: dns.RR_Header{Name: req.Question[0].Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
			A:   m.aIP,
		})
	}
	return resp, nil
}

func (m *mockDNS64Resolver) Configure(cfg core.ResolverConfig) error { return nil }
func (m *mockDNS64Resolver) Shutdown() error                         { return nil }

func TestDNS64Middleware_Synthesis(t *testing.T) {
	synth, err := core.NewDNS64Synthesizer(core.DNS64Config{
		Enabled:  true,
		Prefixes: []string{core.WellKnownDNS64Prefix},
	})
	if err != nil {
		t.Fatalf("failed to create synth: %v", err)
	}

	mockRes := &mockDNS64Resolver{aIP: net.ParseIP("192.0.2.33")}
	mw := NewDNS64Middleware(synth, mockRes)

	// 1. AAAA 查询，下游返回 NODATA
	req := new(dns.Msg)
	req.SetQuestion("ipv4only.example.com.", dns.TypeAAAA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err = mw(ctx, func() error {
		// 模拟下游返回 NODATA 空应答
		resp := new(dns.Msg)
		resp.SetReply(req)
		ctx.Resp = resp
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if ctx.Resp == nil || len(ctx.Resp.Answer) != 1 {
		t.Fatalf("expected 1 synthesized AAAA record, got %d", len(ctx.Resp.Answer))
	}

	aaaa, ok := ctx.Resp.Answer[0].(*dns.AAAA)
	if !ok {
		t.Fatalf("expected *dns.AAAA answer")
	}
	expectedIP := "64:ff9b::c000:221"
	if aaaa.AAAA.String() != expectedIP {
		t.Fatalf("expected %s, got %s", expectedIP, aaaa.AAAA.String())
	}
	if val, ok := ctx.Get("dns64_synthesized"); !ok || val != true {
		t.Fatal("expected dns64_synthesized attribute")
	}

	// 2. 原生已有 AAAA 记录时不得合成
	reqNative := new(dns.Msg)
	reqNative.SetQuestion("dualstack.example.com.", dns.TypeAAAA)
	ctxNative := NewDNSContext(context.Background(), reqNative, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err = mw(ctxNative, func() error {
		resp := new(dns.Msg)
		resp.SetReply(reqNative)
		resp.Answer = append(resp.Answer, &dns.AAAA{
			Hdr:  dns.RR_Header{Name: "dualstack.example.com.", Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: 300},
			AAAA: net.ParseIP("2001:db8::1"),
		})
		ctxNative.Resp = resp
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(ctxNative.Resp.Answer) != 1 {
		t.Fatalf("expected unchanged native AAAA record count, got %d", len(ctxNative.Resp.Answer))
	}
	if _, ok := ctxNative.Get("dns64_synthesized"); ok {
		t.Fatal("dns64_synthesized should NOT be set when native AAAA exists")
	}

	// 3. 原生 AAAA 属于排除集（如 ::1 回环或 fe80:: 链路本地）时，必须允许合成 (RFC 6147 Section 5.1.4)
	reqExcl := new(dns.Msg)
	reqExcl.SetQuestion("loopback-only.example.com.", dns.TypeAAAA)
	ctxExcl := NewDNSContext(context.Background(), reqExcl, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err = mw(ctxExcl, func() error {
		resp := new(dns.Msg)
		resp.SetReply(reqExcl)
		resp.Answer = append(resp.Answer, &dns.AAAA{
			Hdr:  dns.RR_Header{Name: "loopback-only.example.com.", Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: 300},
			AAAA: net.ParseIP("::1"),
		})
		ctxExcl.Resp = resp
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// 包含 ::1 排除集记录 + 合成的有效 IPv6
	if len(ctxExcl.Resp.Answer) < 2 {
		t.Fatalf("expected excluded AAAA + synthesized AAAA, got %d answers", len(ctxExcl.Resp.Answer))
	}

	// 4. NXDOMAIN 权威否定应答时，不得合成且不得发起 A 请求 (RFC 6147 Section 5.1.2)
	reqNX := new(dns.Msg)
	reqNX.SetQuestion("nonexistent.example.com.", dns.TypeAAAA)
	ctxNX := NewDNSContext(context.Background(), reqNX, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err = mw(ctxNX, func() error {
		resp := new(dns.Msg)
		resp.SetReply(reqNX)
		resp.Rcode = dns.RcodeNameError
		ctxNX.Resp = resp
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ctxNX.Resp.Rcode != dns.RcodeNameError || len(ctxNX.Resp.Answer) != 0 {
		t.Fatalf("NXDOMAIN response must remain unmodified, got rcode: %d, answers: %d", ctxNX.Resp.Rcode, len(ctxNX.Resp.Answer))
	}
}

type mockCNAMEResolver struct{}

func (m *mockCNAMEResolver) Resolve(ctx context.Context, raw []byte) ([]byte, error) { return nil, nil }
func (m *mockCNAMEResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Rcode = dns.RcodeSuccess
	// 返回 CNAME 链：alias -> target，以及 target 的 A 记录 (TTL 分别为 120 与 60)
	resp.Answer = append(resp.Answer, &dns.CNAME{
		Hdr:    dns.RR_Header{Name: "alias.example.com.", Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: 120},
		Target: "target.example.com.",
	})
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "target.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
		A:   net.ParseIP("198.51.100.1"),
	})
	return resp, nil
}
func (m *mockCNAMEResolver) Configure(cfg core.ResolverConfig) error { return nil }
func (m *mockCNAMEResolver) Shutdown() error                         { return nil }

func TestDNS64Middleware_CNAMEChainAndTTL(t *testing.T) {
	synth, err := core.NewDNS64Synthesizer(core.DNS64Config{
		Enabled:  true,
		Prefixes: []string{core.WellKnownDNS64Prefix},
	})
	if err != nil {
		t.Fatalf("failed to create synth: %v", err)
	}

	mockRes := &mockCNAMEResolver{}
	mw := NewDNS64Middleware(synth, mockRes)

	req := new(dns.Msg)
	req.SetQuestion("alias.example.com.", dns.TypeAAAA)
	ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err = mw(ctx, func() error {
		// 模拟下游仅返回空应答
		resp := new(dns.Msg)
		resp.SetReply(req)
		ctx.Resp = resp
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// 应答中必须完整保留 CNAME 链并注入合成的 AAAA 记录
	if len(ctx.Resp.Answer) != 2 {
		t.Fatalf("expected 2 records (CNAME + synthesized AAAA), got %d", len(ctx.Resp.Answer))
	}

	cname, ok := ctx.Resp.Answer[0].(*dns.CNAME)
	if !ok || cname.Target != "target.example.com." {
		t.Fatalf("expected CNAME to target.example.com., got %+v", ctx.Resp.Answer[0])
	}

	aaaa, ok := ctx.Resp.Answer[1].(*dns.AAAA)
	if !ok {
		t.Fatalf("expected *dns.AAAA for second record")
	}

	// RFC 6147 Section 5.1.7: 合成的 AAAA TTL 必须为 CNAME(120) 与 A(60) 中的最小值 60
	if aaaa.Hdr.Ttl != 60 {
		t.Fatalf("expected minimum TTL 60, got %d", aaaa.Hdr.Ttl)
	}
}

