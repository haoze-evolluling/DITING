package core

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func TestCoreResolver_IntegrationAndConcurrency(t *testing.T) {
	shutdown, addr, _ := startMockDualServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.2.3.4", r.Question[0].Name))
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	})
	defer shutdown()

	cfg := ResolverConfig{
		Mode: ModeSingle,
		Providers: []ProviderConfig{
			{ID: "plain-main", Protocol: ProtocolPlain, Server: addr},
		},
	}

	resolver, err := NewResolver(cfg)
	if err != nil {
		t.Fatalf("NewResolver failed: %v", err)
	}
	defer func() { _ = resolver.Shutdown() }()

	// 50 协程并发查询模拟
	const concurrency = 50
	var wg sync.WaitGroup
	wg.Add(concurrency)

	for i := 0; i < concurrency; i++ {
		go func(id int) {
			defer wg.Done()
			req := new(dns.Msg)
			req.SetQuestion(dns.Fqdn(fmt.Sprintf("host-%d.test.com", id)), dns.TypeA)
			req.Id = uint16(id + 100)
			req.RecursionDesired = true

			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()

			resp, err := resolver.Exchange(ctx, req)
			if err != nil {
				t.Errorf("concurrent Exchange failed for id %d: %v", id, err)
				return
			}
			if resp.Id != req.Id {
				t.Errorf("mismatched response ID: expected %d, got %d", req.Id, resp.Id)
				return
			}
			if len(resp.Answer) == 0 {
				t.Errorf("empty answer for id %d", id)
			}
		}(i)
	}

	wg.Wait()
}

func TestCoreResolver_ConfigValidation(t *testing.T) {
	// 空上游配置报错
	_, err := NewResolver(ResolverConfig{
		Mode:      ModeSingle,
		Providers: []ProviderConfig{},
	})
	if err == nil {
		t.Fatalf("expected error on empty providers config, got nil")
	}

	// 无效 DoH URL 报错
	_, err = NewResolver(ResolverConfig{
		Mode: ModeSingle,
		Providers: []ProviderConfig{
			{ID: "doh-bad", Protocol: ProtocolDoH, URL: "not-a-url"},
		},
	})
	if err == nil {
		t.Fatalf("expected error on invalid DoH URL, got nil")
	}

	// 空 Server 报错
	_, err = NewResolver(ResolverConfig{
		Mode: ModeSingle,
		Providers: []ProviderConfig{
			{ID: "plain-bad", Protocol: ProtocolPlain, Server: ""},
		},
	})
	if err == nil {
		t.Fatalf("expected error on empty server, got nil")
	}
}

func TestCoreResolver_EdgeCases(t *testing.T) {
	shutdown, addr, _ := startMockDualServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		_ = w.WriteMsg(m)
	})
	defer shutdown()

	resolver, err := NewResolver(ResolverConfig{
		Mode: ModeSingle,
		Providers: []ProviderConfig{
			{ID: "p1", Protocol: ProtocolPlain, Server: addr},
		},
	})
	if err != nil {
		t.Fatalf("NewResolver: %v", err)
	}
	defer func() { _ = resolver.Shutdown() }()

	// nil request error
	_, err = resolver.Exchange(context.Background(), nil)
	if err == nil {
		t.Fatalf("expected error on nil request, got nil")
	}

	// invalid wire query
	_, err = resolver.Resolve(context.Background(), []byte{1, 2, 3})
	if err == nil {
		t.Fatalf("expected error on invalid query wire bytes, got nil")
	}
}

func TestCoreResolver_SetBootstrapAndProtocol(t *testing.T) {
	bs := NewBootstrapResolver(BootstrapConfig{Enabled: false})

	plain := NewPlainResolver(nil)
	plain.SetBootstrap(bs)

	doh := NewDoHResolver(nil)
	doh.SetBootstrap(bs)
	defer doh.Close()

	dot := NewDoTResolver(nil)
	dot.SetBootstrap(bs)
	defer dot.Close()

	if ParseProtocol("doh") != ProtocolDoH || ParseProtocol("https") != ProtocolDoH {
		t.Fatalf("unexpected DoH parse")
	}
	if ParseProtocol("dot") != ProtocolDoT || ParseProtocol("tls") != ProtocolDoT {
		t.Fatalf("unexpected DoT parse")
	}
	if ParseProtocol("plain") != ProtocolPlain || ParseProtocol("unknown") != ProtocolPlain {
		t.Fatalf("unexpected Plain parse")
	}
}
