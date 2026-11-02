package dns

import (
	"context"
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestECHMiddleware(t *testing.T) {
	enabled := true
	mw := NewECHMiddleware(func() bool { return enabled })

	// 1. 开启时剥离 ECH
	req := new(dns.Msg)
	req.SetQuestion("cloudflare.com.", dns.TypeHTTPS)
	dctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")

	err := mw(dctx, func() error {
		resp := new(dns.Msg)
		resp.SetReply(req)
		resp.Answer = append(resp.Answer, &dns.HTTPS{
			SVCB: dns.SVCB{
				Hdr:      dns.RR_Header{Name: "cloudflare.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
				Priority: 1,
				Target:   ".",
				Value: []dns.SVCBKeyValue{
					&dns.SVCBAlpn{Alpn: []string{"h2", "h3"}},
					&dns.SVCBECHConfig{ECH: []byte{0x01, 0x02, 0x03}},
				},
			},
		})
		dctx.Resp = resp
		return nil
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	stripped, _ := dctx.Get("ech_stripped")
	if stripped != true {
		t.Fatal("expected ech_stripped to be true")
	}

	httpsRR := dctx.Resp.Answer[0].(*dns.HTTPS)
	for _, kv := range httpsRR.Value {
		if kv.Key() == dns.SVCB_ECHCONFIG {
			t.Fatal("expected ECH parameter to be stripped")
		}
	}

	// 2. 禁用时不修改
	enabled = false
	dctx2 := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	err2 := mw(dctx2, func() error {
		resp := new(dns.Msg)
		resp.SetReply(req)
		resp.Answer = append(resp.Answer, &dns.HTTPS{
			SVCB: dns.SVCB{
				Hdr:      dns.RR_Header{Name: "cloudflare.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
				Priority: 1,
				Target:   ".",
				Value: []dns.SVCBKeyValue{
					&dns.SVCBECHConfig{ECH: []byte{0x01, 0x02, 0x03}},
				},
			},
		})
		dctx2.Resp = resp
		return nil
	})
	if err2 != nil {
		t.Fatalf("unexpected error: %v", err2)
	}

	stripped2, _ := dctx2.Get("ech_stripped")
	if stripped2 == true {
		t.Fatal("expected ech_stripped to be false when disabled")
	}
	httpsRR2 := dctx2.Resp.Answer[0].(*dns.HTTPS)
	if len(httpsRR2.Value) != 1 {
		t.Fatal("expected ECH parameter to remain intact when disabled")
	}
}
