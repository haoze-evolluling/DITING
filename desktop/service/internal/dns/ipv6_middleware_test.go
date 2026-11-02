package dns

import (
	"context"
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestIPv6Middleware(t *testing.T) {
	enabled := true
	mw := NewIPv6Middleware(func() bool { return enabled })

	// 1. AAAA 查询拦截并返回权威 NODATA
	req := new(dns.Msg)
	req.SetQuestion("test.example.com.", dns.TypeAAAA)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	nextCalled := false
	err := mw(dctx, func() error {
		nextCalled = true
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if nextCalled {
		t.Fatal("expected next() not to be called for AAAA when BlockIPv6 is enabled")
	}
	if dctx.Resp == nil {
		t.Fatal("expected synthetic response")
	}
	if dctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("expected NOERROR (0), got %d", dctx.Resp.Rcode)
	}
	if len(dctx.Resp.Answer) != 0 {
		t.Fatalf("expected empty Answer for NODATA, got %d records", len(dctx.Resp.Answer))
	}
	if len(dctx.Resp.Ns) == 0 {
		t.Fatal("expected SOA record in NS section")
	}
	if src, _ := dctx.Get("source"); src != "block_ipv6" {
		t.Fatalf("expected source=block_ipv6, got %v", src)
	}
	if blocked, _ := dctx.Get("ipv6_blocked"); blocked != true {
		t.Fatalf("expected ipv6_blocked=true, got %v", blocked)
	}

	// 2. A 记录查询不受影响，正常透传至下层
	reqA := new(dns.Msg)
	reqA.SetQuestion("test.example.com.", dns.TypeA)
	dctxA := NewDNSContext(context.Background(), reqA, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	nextCalledA := false
	errA := mw(dctxA, func() error {
		nextCalledA = true
		return nil
	})
	if errA != nil || !nextCalledA {
		t.Fatalf("expected TypeA to pass through to next(), nextCalled=%v, err=%v", nextCalledA, errA)
	}

	// 3. 动态禁用后，AAAA 恢复透传
	enabled = false
	dctxDisabled := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	nextCalledDisabled := false
	errDisabled := mw(dctxDisabled, func() error {
		nextCalledDisabled = true
		return nil
	})
	if errDisabled != nil || !nextCalledDisabled {
		t.Fatalf("expected AAAA to pass through when disabled, nextCalled=%v, err=%v", nextCalledDisabled, errDisabled)
	}
}

func TestIPv6Middleware_StripIPv6Hints(t *testing.T) {
	enabled := true
	mw := NewIPv6Middleware(func() bool { return enabled })

	// 创建包含 ipv4hint 与 ipv6hint 的 HTTPS 响应
	makeHTTPSMsg := func() *dns.Msg {
		msg := new(dns.Msg)
		msg.SetQuestion("svc.example.com.", dns.TypeHTTPS)
		msg.Answer = append(msg.Answer, &dns.HTTPS{
			SVCB: dns.SVCB{
				Hdr:      dns.RR_Header{Name: "svc.example.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
				Priority: 1,
				Target:   ".",
				Value: []dns.SVCBKeyValue{
					&dns.SVCBAlpn{Alpn: []string{"h2", "h3"}},
					&dns.SVCBIPv4Hint{Hint: []net.IP{net.ParseIP("1.2.3.4")}},
					&dns.SVCBIPv6Hint{Hint: []net.IP{net.ParseIP("2001:db8::1")}},
				},
			},
		})
		return msg
	}

	// 1. 开启 BlockIPv6 时，下层返回的 HTTPS 记录中的 ipv6hint 应被自动剥离
	req := new(dns.Msg)
	req.SetQuestion("svc.example.com.", dns.TypeHTTPS)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err := mw(dctx, func() error {
		dctx.Resp = makeHTTPSMsg()
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dctx.Resp == nil || len(dctx.Resp.Answer) != 1 {
		t.Fatalf("expected answer in response, got %v", dctx.Resp)
	}
	httpsRR, ok := dctx.Resp.Answer[0].(*dns.HTTPS)
	if !ok {
		t.Fatalf("expected HTTPS record, got %T", dctx.Resp.Answer[0])
	}
	for _, kv := range httpsRR.Value {
		if kv.Key() == dns.SVCB_IPV6HINT {
			t.Fatal("expected ipv6hint to be stripped when BlockIPv6 is enabled")
		}
	}
	if stripped, _ := dctx.Get("ipv6_hints_stripped"); stripped != true {
		t.Fatal("expected ipv6_hints_stripped=true")
	}

	// 2. 关闭 BlockIPv6 时，ipv6hint 正常保留
	enabled = false
	dctx2 := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	err2 := mw(dctx2, func() error {
		dctx2.Resp = makeHTTPSMsg()
		return nil
	})
	if err2 != nil {
		t.Fatalf("unexpected error: %v", err2)
	}
	httpsRR2 := dctx2.Resp.Answer[0].(*dns.HTTPS)
	hasIPv6Hint := false
	for _, kv := range httpsRR2.Value {
		if kv.Key() == dns.SVCB_IPV6HINT {
			hasIPv6Hint = true
		}
	}
	if !hasIPv6Hint {
		t.Fatal("expected ipv6hint to be preserved when BlockIPv6 is disabled")
	}
}

