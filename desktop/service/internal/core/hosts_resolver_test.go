package core

import (
	"strings"
	"testing"

	"github.com/miekg/dns"
)

func TestHostsResolver_LoadReaderAndLookup(t *testing.T) {
	content := `
# System hosts mock
127.0.0.1 localhost myapp.local
192.168.1.100 nas.home storage.home # lan nas
::1 localhost ip6-localhost
2001:db8::1 ipv6.test.local
fe80::1%eth0 linklocal.local
`
	hr, err := NewHostsResolver(HostsConfig{Enabled: false})
	if err != nil {
		t.Fatalf("failed to create HostsResolver: %v", err)
	}

	hr.LoadReader(strings.NewReader(content))

	// Test IPv4 lookup
	answersA := hr.Lookup("myapp.local", dns.TypeA)
	if len(answersA) != 1 {
		t.Fatalf("expected 1 A record for myapp.local, got %d", len(answersA))
	}
	aRecord, ok := answersA[0].(*dns.A)
	if !ok || aRecord.A.String() != "127.0.0.1" {
		t.Fatalf("expected 127.0.0.1, got %v", answersA[0])
	}

	// Test IPv6 lookup
	answersAAAA := hr.Lookup("ipv6.test.local", dns.TypeAAAA)
	if len(answersAAAA) != 1 {
		t.Fatalf("expected 1 AAAA record for ipv6.test.local, got %d", len(answersAAAA))
	}
	aaaaRecord, ok := answersAAAA[0].(*dns.AAAA)
	if !ok || aaaaRecord.AAAA.String() != "2001:db8::1" {
		t.Fatalf("expected 2001:db8::1, got %v", answersAAAA[0])
	}

	// Test Zone Scope stripping
	linkAnswers := hr.Lookup("linklocal.local", dns.TypeAAAA)
	if len(linkAnswers) != 1 {
		t.Fatalf("expected 1 AAAA record for linklocal.local, got %d", len(linkAnswers))
	}

	// Test HasDomain
	if !hr.HasDomain("myapp.local") || !hr.HasDomain("storage.home") {
		t.Fatal("expected HasDomain to be true for hosts entries")
	}
	if hr.HasDomain("notfound.com") {
		t.Fatal("expected HasDomain to be false for non-existent domain")
	}

	// Test not found
	notFound := hr.Lookup("notfound.com", dns.TypeA)
	if len(notFound) != 0 {
		t.Fatalf("expected 0 records for non-existent domain, got %d", len(notFound))
	}

	// Test Reverse PTR lookup (支持所有映射别名)
	ptrAnswers := hr.LookupPTR("100.1.168.192.in-addr.arpa.")
	if len(ptrAnswers) != 2 {
		t.Fatalf("expected 2 PTR records for 192.168.1.100 aliases, got %d", len(ptrAnswers))
	}
	names := []string{ptrAnswers[0].(*dns.PTR).Ptr, ptrAnswers[1].(*dns.PTR).Ptr}
	if names[0] != "nas.home." || names[1] != "storage.home." {
		t.Fatalf("unexpected PTR records: %v", names)
	}
}

func TestParseIPFromArpa(t *testing.T) {
	// Valid IPv4
	ip4 := ParseIPFromArpa("1.1.168.192.in-addr.arpa.")
	if ip4 == nil || ip4.String() != "192.168.1.1" {
		t.Fatalf("expected 192.168.1.1, got %v", ip4)
	}

	// Valid IPv6: 2001:db8::1
	// 1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.
	ip6 := ParseIPFromArpa("1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.")
	if ip6 == nil || ip6.String() != "2001:db8::1" {
		t.Fatalf("expected 2001:db8::1, got %v", ip6)
	}

	// Invalid
	bad := ParseIPFromArpa("invalid.in-addr.arpa")
	if bad != nil {
		t.Fatalf("expected nil for invalid arpa, got %v", bad)
	}
}
