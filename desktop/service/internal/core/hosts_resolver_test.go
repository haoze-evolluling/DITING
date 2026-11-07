package core

import (
	"net"
	"os"
	"path/filepath"
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

func writeHostsFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
	return path
}

func TestHostsResolver_ReloadRereadsTheLoadedFiles(t *testing.T) {
	dir := t.TempDir()
	path := writeHostsFile(t, dir, "custom.hosts", "10.0.0.1 nas.home\n")

	hr, err := NewHostsResolver(HostsConfig{Enabled: true, CustomFiles: []string{path}, TTL: 30})
	if err != nil {
		t.Fatalf("failed to create HostsResolver: %v", err)
	}
	if answers := hr.Lookup("nas.home", dns.TypeA); len(answers) != 1 {
		t.Fatalf("expected 1 A record, got %d", len(answers))
	}

	writeHostsFile(t, dir, "custom.hosts", "10.0.0.9 nas.home\n")
	if err := hr.Reload(); err != nil {
		t.Fatalf("reload: %v", err)
	}
	answers := hr.Lookup("nas.home", dns.TypeA)
	if len(answers) != 1 || answers[0].(*dns.A).A.String() != "10.0.0.9" {
		t.Fatalf("after reload: %v", answers)
	}
	if got := answers[0].Header().Ttl; got != 30 {
		t.Fatalf("ttl = %d", got)
	}
}

func TestHostsResolver_UpdateConfigReplacesTheMaps(t *testing.T) {
	dir := t.TempDir()
	first := writeHostsFile(t, dir, "first.hosts", "10.0.0.1 old.home\n")
	second := writeHostsFile(t, dir, "second.hosts", "10.0.0.2 new.home\n")

	hr, err := NewHostsResolver(HostsConfig{Enabled: true, CustomFiles: []string{first}})
	if err != nil {
		t.Fatalf("failed to create HostsResolver: %v", err)
	}
	if !hr.HasDomain("old.home") {
		t.Fatal("expected the first file to be loaded")
	}

	if err := hr.UpdateConfig(HostsConfig{Enabled: true, CustomFiles: []string{second}, TTL: 90}); err != nil {
		t.Fatalf("update: %v", err)
	}
	if hr.HasDomain("old.home") {
		t.Fatal("old entries survived the configuration change")
	}
	if !hr.HasDomain("new.home") {
		t.Fatal("new entries are missing")
	}
	answers := hr.Lookup("new.home", dns.TypeA)
	if len(answers) != 1 || answers[0].Header().Ttl != 90 {
		t.Fatalf("answers = %v", answers)
	}

	// A disabled configuration keeps an empty table and no loaded files.
	if err := hr.UpdateConfig(HostsConfig{Enabled: false}); err != nil {
		t.Fatalf("disable: %v", err)
	}
	if hr.IsEnabled() || hr.HasDomain("new.home") {
		t.Fatal("disabled resolver still answers")
	}
	if answers := hr.Lookup("new.home", dns.TypeA); len(answers) != 0 {
		t.Fatalf("answers = %v", answers)
	}
}

func TestHostsResolver_DisabledWithoutFilesIsSilent(t *testing.T) {
	hr, err := NewHostsResolver(HostsConfig{Enabled: false})
	if err != nil {
		t.Fatalf("failed to create HostsResolver: %v", err)
	}
	if hr.HasDomain("localhost") || len(hr.Lookup("localhost", dns.TypeA)) != 0 {
		t.Fatal("disabled resolver answered")
	}
	if records := hr.LookupPTR("1.0.0.127.in-addr.arpa."); len(records) != 0 {
		t.Fatalf("ptr records = %v", records)
	}
	if name := hr.LookupReverse(net.IPv4(127, 0, 0, 1)); name != "" {
		t.Fatalf("reverse = %q", name)
	}
}

func TestHostsResolver_LoadFileReportsUnreadablePaths(t *testing.T) {
	dir := t.TempDir()
	missing := filepath.Join(dir, "missing.hosts")
	hr, err := NewHostsResolver(HostsConfig{Enabled: true})
	if err != nil {
		t.Fatalf("failed to create HostsResolver: %v", err)
	}
	if err := hr.LoadFile(missing); err == nil {
		t.Fatal("expected an error for a missing file")
	}
	// The failed path is not remembered, so a reload does not retry it.
	if err := hr.Reload(); err != nil {
		t.Fatalf("reload: %v", err)
	}
}

func TestHostsResolver_ReverseLookupReturnsEveryAlias(t *testing.T) {
	hr, err := NewHostsResolver(HostsConfig{Enabled: false})
	if err != nil {
		t.Fatalf("failed to create HostsResolver: %v", err)
	}
	hr.LoadReader(strings.NewReader("192.168.1.100 nas.home storage.home\n"))
	if name := hr.LookupReverse(net.IPv4(192, 168, 1, 100)); name != "nas.home" {
		t.Fatalf("reverse = %q", name)
	}
	if name := hr.LookupReverse(net.ParseIP("::ffff:192.168.1.100")); name != "nas.home" {
		t.Fatalf("mapped reverse = %q", name)
	}
	if name := hr.LookupReverse(net.IPv4(192, 168, 1, 101)); name != "" {
		t.Fatalf("unknown reverse = %q", name)
	}
}
