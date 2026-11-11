package core

import (
	"context"
	"testing"

	"github.com/miekg/dns"
)

type mockResolver struct {
	tag string
}

func (m *mockResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	msg := new(dns.Msg)
	_ = msg.Unpack(rawQuery)
	resp, _ := m.Exchange(ctx, msg)
	return resp.Pack()
}

func (m *mockResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Rcode = dns.RcodeSuccess
	resp.Extra = append(resp.Extra, &dns.TXT{
		Hdr: dns.RR_Header{Name: req.Question[0].Name, Rrtype: dns.TypeTXT, Class: dns.ClassINET, Ttl: 60},
		Txt: []string{m.tag},
	})
	return resp, nil
}

func (m *mockResolver) Configure(cfg ResolverConfig) error { return nil }
func (m *mockResolver) Shutdown() error                    { return nil }

func TestConditionalRouter_Routing(t *testing.T) {
	defaultRes := &mockResolver{tag: "default"}
	corpRes := &mockResolver{tag: "corp"}
	subCorpRes := &mockResolver{tag: "subcorp"}

	router := NewConditionalRouter(defaultRes)
	router.SetRoute("corp.internal", corpRes)
	router.SetRoute("secure.corp.internal", subCorpRes)

	ctx := context.Background()

	// 1. Fallback to default
	reqDefault := new(dns.Msg)
	reqDefault.SetQuestion("google.com.", dns.TypeA)
	respDefault, err := router.Exchange(ctx, reqDefault)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	txt := respDefault.Extra[0].(*dns.TXT).Txt[0]
	if txt != "default" {
		t.Fatalf("expected default resolver, got %s", txt)
	}

	// 2. Match corp.internal
	reqCorp := new(dns.Msg)
	reqCorp.SetQuestion("wiki.corp.internal.", dns.TypeA)
	respCorp, err := router.Exchange(ctx, reqCorp)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	txt = respCorp.Extra[0].(*dns.TXT).Txt[0]
	if txt != "corp" {
		t.Fatalf("expected corp resolver, got %s", txt)
	}

	// 3. Match longest suffix secure.corp.internal
	reqSecure := new(dns.Msg)
	reqSecure.SetQuestion("api.secure.corp.internal.", dns.TypeA)
	respSecure, err := router.Exchange(ctx, reqSecure)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	txt = respSecure.Extra[0].(*dns.TXT).Txt[0]
	if txt != "subcorp" {
		t.Fatalf("expected subcorp resolver, got %s", txt)
	}

	// 4. Remove route and fallback
	router.RemoveRoute("secure.corp.internal")
	respRemoved, _ := router.Exchange(ctx, reqSecure)
	txt = respRemoved.Extra[0].(*dns.TXT).Txt[0]
	if txt != "corp" {
		t.Fatalf("expected fallback to corp resolver after remove, got %s", txt)
	}
}
