package dns

import (
	"context"
	"net"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

func TestPrivatePTR_LocallyServedZones(t *testing.T) {
	mw := NewPrivatePTRMiddleware(func() bool { return true }, nil)

	testCases := []struct {
		name       string
		qname      string
		qtype      uint16
		shouldDrop bool // true 表示应被中间件权威拦截返回 NXDOMAIN
	}{
		// RFC 1918
		{"192.168.1.1", "1.1.168.192.in-addr.arpa.", dns.TypePTR, true},
		{"10.20.30.40", "40.30.20.10.in-addr.arpa.", dns.TypePTR, true},
		{"172.16.0.1", "1.0.16.172.in-addr.arpa.", dns.TypePTR, true},
		{"172.31.255.254", "254.255.31.172.in-addr.arpa.", dns.TypePTR, true},

		// RFC 6598 / RFC 7793 CGNAT
		{"100.64.0.1", "1.0.64.100.in-addr.arpa.", dns.TypePTR, true},
		{"100.127.1.1", "1.1.127.100.in-addr.arpa.", dns.TypePTR, true},

		// 链路本地与回环
		{"169.254.1.2", "2.1.254.169.in-addr.arpa.", dns.TypePTR, true},
		{"127.0.0.1", "1.0.0.127.in-addr.arpa.", dns.TypePTR, true},
		{"0.0.0.0", "0.0.0.0.in-addr.arpa.", dns.TypePTR, true},
		{"255.255.255.255", "255.255.255.255.in-addr.arpa.", dns.TypePTR, true},

		// IPv6 ULA & Link-Local
		{"IPv6 ULA", "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.d.f.ip6.arpa.", dns.TypePTR, true},
		{"IPv6 Link-Local", "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.f.ip6.arpa.", dns.TypePTR, true},

		// 公网 IP PTR 不应拦截
		{"Public 8.8.8.8", "8.8.8.8.in-addr.arpa.", dns.TypePTR, false},
		{"Public 1.1.1.1", "1.1.1.1.in-addr.arpa.", dns.TypePTR, false},
		{"Public 114.114.114.114", "114.114.114.114.in-addr.arpa.", dns.TypePTR, false},

		// 非 PTR 类型请求不应拦截
		{"192.168.1.1 TypeA", "1.1.168.192.in-addr.arpa.", dns.TypeA, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			req := new(dns.Msg)
			req.SetQuestion(tc.qname, tc.qtype)
			dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

			nextCalled := false
			err := mw(dctx, func() error {
				nextCalled = true
				return nil
			})
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if tc.shouldDrop {
				if nextCalled {
					t.Fatalf("expected query %s to be blocked by locally served zone, but next() was called", tc.qname)
				}
				if dctx.Resp == nil {
					t.Fatalf("expected synthetic response for %s", tc.qname)
				}
				if dctx.Resp.Rcode != dns.RcodeNameError {
					t.Fatalf("expected NXDOMAIN (3), got %d (%s)", dctx.Resp.Rcode, dns.RcodeToString[dctx.Resp.Rcode])
				}
				if !dctx.Resp.Authoritative {
					t.Fatal("expected authoritative response")
				}
				if len(dctx.Resp.Ns) == 0 {
					t.Fatal("expected SOA record in NS section")
				}
				if soa, ok := dctx.Resp.Ns[0].(*dns.SOA); !ok || soa.Hdr.Rrtype != dns.TypeSOA {
					t.Fatal("expected valid SOA RR in NS section")
				}
				if src, _ := dctx.Get("source"); src != "locally_served_zone" {
					t.Fatalf("expected source=locally_served_zone, got %v", src)
				}
				if blocked, _ := dctx.Get("private_ptr_blocked"); blocked != true {
					t.Fatalf("expected private_ptr_blocked=true, got %v", blocked)
				}
			} else {
				if !nextCalled {
					t.Fatalf("expected query %s to pass through to next(), but was intercepted", tc.qname)
				}
			}
		})
	}
}

func TestPrivatePTR_Disabled(t *testing.T) {
	mw := NewPrivatePTRMiddleware(func() bool { return false }, nil)
	req := new(dns.Msg)
	req.SetQuestion("1.1.168.192.in-addr.arpa.", dns.TypePTR)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	nextCalled := false
	err := mw(dctx, func() error {
		nextCalled = true
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !nextCalled {
		t.Fatal("expected next() to be called when middleware is disabled")
	}
}

func TestPrivatePTR_WithClientResolver(t *testing.T) {
	cr := core.NewClientResolver(core.ClientConfig{
		Enabled: true,
		Aliases: []core.ClientAlias{
			{IP: "192.168.1.100", Name: "my-smart-tv.lan"},
		},
	})

	mw := NewPrivatePTRMiddleware(func() bool { return true }, cr)

	// 1. 命中客户端解析器的私有 IP
	req := new(dns.Msg)
	req.SetQuestion("100.1.168.192.in-addr.arpa.", dns.TypePTR)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err := mw(dctx, func() error {
		t.Fatal("next() should not be called when clientResolver matches")
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dctx.Resp == nil {
		t.Fatal("expected response")
	}
	if dctx.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("expected NOERROR (0), got %d", dctx.Resp.Rcode)
	}
	if len(dctx.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(dctx.Resp.Answer))
	}
	ptr, ok := dctx.Resp.Answer[0].(*dns.PTR)
	if !ok || ptr.Ptr != "my-smart-tv.lan." {
		t.Fatalf("expected PTR my-smart-tv.lan., got %v", dctx.Resp.Answer[0])
	}
	if src, _ := dctx.Get("source"); src != "client_resolver_ptr" {
		t.Fatalf("expected source=client_resolver_ptr, got %v", src)
	}

	// 2. 未命中客户端解析器的其他私有 IP -> 依然权威拦截为 NXDOMAIN
	req2 := new(dns.Msg)
	req2.SetQuestion("200.1.168.192.in-addr.arpa.", dns.TypePTR)
	dctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err2 := mw(dctx2, func() error {
		t.Fatal("next() should not be called for unmapped private PTR")
		return nil
	})
	if err2 != nil {
		t.Fatalf("unexpected error: %v", err2)
	}
	if dctx2.Resp == nil || dctx2.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("expected NXDOMAIN for unmapped private PTR, got %v", dctx2.Resp)
	}

	// 3. IPv6 客户端别名命中与反向解析验证
	crIPv6 := core.NewClientResolver(core.ClientConfig{
		Enabled: true,
		Aliases: []core.ClientAlias{
			{IP: "fd00::1", Name: "my-ipv6-server.lan"},
		},
	})
	mwIPv6 := NewPrivatePTRMiddleware(func() bool { return true }, crIPv6)
	ptrIPv6, errRev := dns.ReverseAddr("fd00::1")
	if errRev != nil {
		t.Fatalf("reverse addr failed: %v", errRev)
	}
	reqIPv6 := new(dns.Msg)
	reqIPv6.SetQuestion(ptrIPv6, dns.TypePTR)
	dctxIPv6 := NewDNSContext(context.Background(), reqIPv6, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err3 := mwIPv6(dctxIPv6, func() error {
		t.Fatal("next() should not be called when IPv6 clientResolver matches")
		return nil
	})
	if err3 != nil {
		t.Fatalf("unexpected error: %v", err3)
	}
	if dctxIPv6.Resp == nil || dctxIPv6.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("expected NOERROR for mapped IPv6 PTR, got %v", dctxIPv6.Resp)
	}
	if len(dctxIPv6.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer for IPv6 PTR, got %d", len(dctxIPv6.Resp.Answer))
	}
	ansIPv6, ok := dctxIPv6.Resp.Answer[0].(*dns.PTR)
	if !ok || ansIPv6.Ptr != "my-ipv6-server.lan." {
		t.Fatalf("expected PTR my-ipv6-server.lan., got %v", dctxIPv6.Resp.Answer[0])
	}
}

func TestParsePTRIP(t *testing.T) {
	testCases := []struct {
		name     string
		ptrName  string
		expected string // 期望的 IP 字符串，若为 "" 则期望返回 nil
	}{
		{"IPv4 valid", "1.2.168.192.in-addr.arpa.", "192.168.2.1"},
		{"IPv4 loopback", "1.0.0.127.in-addr.arpa", "127.0.0.1"},
		{"IPv4 overflow octet", "999.1.168.192.in-addr.arpa.", ""},
		{"IPv4 too few labels", "1.168.192.in-addr.arpa.", ""},
		{"IPv4 invalid char", "abc.1.168.192.in-addr.arpa.", ""},
		{"IPv6 loopback ::1", "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa.", "::1"},
		{"IPv6 ULA fd00::1", "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.d.f.ip6.arpa.", "fd00::1"},
		{"IPv6 link-local fe80::2", "2.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.f.ip6.arpa.", "fe80::2"},
		{"IPv6 standard RFC 3596 example", "b.a.9.8.7.6.5.0.4.0.0.0.3.0.0.0.2.0.0.0.1.0.0.0.0.0.0.0.1.2.3.4.ip6.arpa.", "4321:0:1:2:3:4:567:89ab"},
		{"IPv6 invalid length", "1.2.3.ip6.arpa.", ""},
		{"IPv6 invalid char", "g.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.d.f.ip6.arpa.", ""},
		{"Not a PTR name", "example.com.", ""},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			res := ParsePTRIP(tc.ptrName)
			if tc.expected == "" {
				if res != nil {
					t.Fatalf("expected nil for %s, got %s", tc.ptrName, res.String())
				}
			} else {
				if res == nil {
					t.Fatalf("expected %s for %s, got nil", tc.expected, tc.ptrName)
				}
				expectedIP := net.ParseIP(tc.expected)
				if !res.Equal(expectedIP) {
					t.Fatalf("expected %s (%v), got %s (%v)", tc.expected, expectedIP, res.String(), res)
				}
			}
		})
	}
}
