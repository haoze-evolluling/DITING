package core

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func TestBootstrap_AddressValidation(t *testing.T) {
	validCases := []BootstrapConfig{
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bs1", Address: "223.5.5.5"},
				{ID: "bs2", Address: "119.29.29.29:53"},
				{ID: "bs3", Address: "2400:3200::1"},
				{ID: "bs4", Address: "[2400:3200::1]:53"},
			},
		},
		{
			Enabled: false,
			Servers: []BootstrapServer{},
		},
	}

	for i, tc := range validCases {
		if err := ValidateBootstrapConfig(tc); err != nil {
			t.Fatalf("case %d: expected valid, got error: %v", i, err)
		}
	}

	invalidCases := []BootstrapConfig{
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad1", Address: "dns.alidns.com"},
			},
		},
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad2", Address: ""},
			},
		},
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad3", Address: "999.999.999.999"},
			},
		},
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad4", Address: "223.5.5.5:abc"},
			},
		},
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad5", Address: "223.5.5.5:0"},
			},
		},
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad6", Address: "223.5.5.5:65536"},
			},
		},
		{
			Enabled: true,
			Servers: []BootstrapServer{
				{ID: "bad7", Address: "[2400:3200::1]:abc"},
			},
		},
	}

	for i, tc := range invalidCases {
		if err := ValidateBootstrapConfig(tc); err == nil {
			t.Fatalf("case %d: expected validation error for %v, got nil", i, tc.Servers)
		}
	}
}

func TestDoT_BootstrapHostnameResolution(t *testing.T) {
	dotListener, dotAddr := startMockDoTServer(t)
	defer dotListener.Close()

	_, dotPort, err := net.SplitHostPort(dotAddr)
	if err != nil {
		t.Fatalf("split host port: %v", err)
	}

	// 模拟 Bootstrap DNS，将 dot.upstream.test 解析为 127.0.0.1
	dnsSrv, dnsAddr := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		if len(r.Question) > 0 && r.Question[0].Qtype == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 127.0.0.1", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		}
		_ = w.WriteMsg(m)
	})
	defer func() { _ = dnsSrv.Shutdown() }()

	bs := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "mock-bs", Name: "MockDNS", Address: dnsAddr},
		},
	})

	dot := NewDoTResolver(bs)
	dot.SetTLSConfig(&tls.Config{
		InsecureSkipVerify: true,
	})
	defer dot.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("example.org")
	// 使用域名访问 DoT 服务器，触发 Bootstrap 解析
	resp, err := dot.Exchange(ctx, rawQuery, fmt.Sprintf("dot.upstream.test:%s", dotPort))
	if err != nil {
		t.Fatalf("DoT Exchange with bootstrap failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack DoT response failed: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(respMsg.Answer))
	}
}

func TestDoH_BootstrapHostnameResolution(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Content-Type") != "application/dns-message" {
			http.Error(w, "bad content type", http.StatusBadRequest)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		var qMsg dns.Msg
		if err := qMsg.Unpack(body); err != nil {
			http.Error(w, "unpack query failed", http.StatusBadRequest)
			return
		}

		respMsg := new(dns.Msg)
		respMsg.SetReply(&qMsg)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.2.3.4", qMsg.Question[0].Name))
		respMsg.Answer = append(respMsg.Answer, rr)

		respBytes, _ := respMsg.Pack()
		w.Header().Set("Content-Type", "application/dns-message")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(respBytes)
	}))
	defer ts.Close()

	_, dohPort, err := net.SplitHostPort(ts.Listener.Addr().String())
	if err != nil {
		t.Fatalf("split host port: %v", err)
	}

	// 模拟 Bootstrap DNS，将 doh.upstream.test 解析为 127.0.0.1
	dnsSrv, dnsAddr := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		if len(r.Question) > 0 && r.Question[0].Qtype == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 127.0.0.1", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		}
		_ = w.WriteMsg(m)
	})
	defer func() { _ = dnsSrv.Shutdown() }()

	bs := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "mock-bs", Name: "MockDNS", Address: dnsAddr},
		},
	})

	doh := NewDoHResolver(bs)
	defer doh.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("example.org")
	dohURL := fmt.Sprintf("http://doh.upstream.test:%s/dns-query", dohPort)
	resp, err := doh.Exchange(ctx, rawQuery, dohURL)
	if err != nil {
		t.Fatalf("DoH Exchange with bootstrap failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack DoH response failed: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(respMsg.Answer))
	}
}

func TestDoT_BootstrapFailover(t *testing.T) {
	dotListener, dotAddr := startMockDoTServer(t)
	defer dotListener.Close()

	_, dotPort, _ := net.SplitHostPort(dotAddr)

	// 第二个 Bootstrap 正常响应
	dnsSrv2, dnsAddr2 := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		if len(r.Question) > 0 && r.Question[0].Qtype == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 127.0.0.1", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		}
		_ = w.WriteMsg(m)
	})
	defer func() { _ = dnsSrv2.Shutdown() }()

	// 第一个 Bootstrap 指向一个无法连接的无效端口 127.0.0.1:19999
	bs := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "bs-fail", Name: "FailDNS", Address: "127.0.0.1:19999", Weight: 100.0},
			{ID: "bs-ok", Name: "OkDNS", Address: dnsAddr2, Weight: 1.0},
		},
	})

	dot := NewDoTResolver(bs)
	dot.SetTLSConfig(&tls.Config{InsecureSkipVerify: true})
	defer dot.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("example.org")
	resp, err := dot.Exchange(ctx, rawQuery, fmt.Sprintf("dot.failover.test:%s", dotPort))
	if err != nil {
		t.Fatalf("DoT Exchange failover failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack response failed: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer from failover DoT, got %d", len(respMsg.Answer))
	}
}

func TestBootstrap_DuplicateOrEmptyIDs_NoDropFallbacks(t *testing.T) {
	bs := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "", Name: "S1", Address: "1.1.1.1:53"},
			{ID: "", Name: "S2", Address: "8.8.8.8:53"},
			{ID: "", Name: "S3", Address: "9.9.9.9:53"},
		},
	})

	plan := bs.choosePlan(bs.servers, time.Now())
	if plan.primary.Address == "" {
		t.Fatalf("expected non-empty primary server")
	}
	if len(plan.fallbacks) != 2 {
		t.Fatalf("expected 2 fallbacks even with empty IDs, got %d", len(plan.fallbacks))
	}

	bsDup := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "same-id", Name: "S1", Address: "1.1.1.1:53"},
			{ID: "same-id", Name: "S2", Address: "8.8.8.8:53"},
		},
	})
	planDup := bsDup.choosePlan(bsDup.servers, time.Now())
	if len(planDup.fallbacks) != 1 {
		t.Fatalf("expected 1 fallback with duplicate IDs, got %d", len(planDup.fallbacks))
	}
}

func TestBootstrap_FQDNTrailingDotResolution(t *testing.T) {
	dnsSrv, dnsAddr := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		if len(r.Question) > 0 && r.Question[0].Qtype == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.2.3.4", r.Question[0].Name))
			m.Answer = append(m.Answer, rr)
		}
		_ = w.WriteMsg(m)
	})
	defer func() { _ = dnsSrv.Shutdown() }()

	bs := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{
			{ID: "bs-1", Address: dnsAddr},
		},
	})

	ctx := context.Background()
	ip1, err := bs.ResolveHost(ctx, "dot.example.test.")
	if err != nil {
		t.Fatalf("ResolveHost with trailing dot failed: %v", err)
	}
	if ip1 != "1.2.3.4" {
		t.Fatalf("expected 1.2.3.4, got %s", ip1)
	}

	// 确认缓存同时命中无点域名
	cached, ok := bs.getCached("dot.example.test")
	if !ok || cached != "1.2.3.4" {
		t.Fatalf("expected normalized cache hit for dot.example.test, got cached=%q, ok=%v", cached, ok)
	}
}
