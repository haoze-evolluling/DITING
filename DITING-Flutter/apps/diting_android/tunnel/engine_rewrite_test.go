package tunnel

import (
	"encoding/json"
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestSetRewriteRulesParsesStringAndArrayValues(t *testing.T) {
	e := NewEngine()

	e.SetRewriteRules(`{
		"github.com": "140.82.112.3",
		"example.com": ["93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"],
		"alias.example.org": "origin.example.net",
		"empty.example": [],
		"bad.example": 42
	}`)

	if ip := e.rewriteIP("github.com", true); ip == nil || ip.String() != "140.82.112.3" {
		t.Fatalf("ipv4 rewrite for github.com = %v, want 140.82.112.3", ip)
	}
	if ip := e.rewriteIP("github.com", false); ip != nil {
		t.Fatalf("ipv6 rewrite for github.com = %v, want nil", ip)
	}
	if ip := e.rewriteIP("example.com", true); ip == nil || ip.String() != "93.184.216.34" {
		t.Fatalf("ipv4 rewrite for example.com = %v, want 93.184.216.34", ip)
	}
	if ip := e.rewriteIP("example.com", false); ip == nil || ip.String() != "2606:2800:220:1:248:1893:25c8:1946" {
		t.Fatalf("ipv6 rewrite for example.com = %v, want 2606:2800:220:1:248:1893:25c8:1946", ip)
	}
	if target := e.rewriteCNAME("alias.example.org"); target != "origin.example.net" {
		t.Fatalf("cname rewrite = %q, want origin.example.net", target)
	}
	if ip := e.rewriteIP("empty.example", true); ip != nil {
		t.Fatalf("ipv4 rewrite for empty.example = %v, want nil", ip)
	}
	if ip := e.rewriteIP("bad.example", true); ip != nil {
		t.Fatalf("ipv4 rewrite for bad.example = %v, want nil", ip)
	}
}

func TestRewriteLookupSuffixMatchingAndCase(t *testing.T) {
	e := NewEngine()

	e.SetRewriteRules(`{"GitHub.COM.": "140.82.112.3"}`)

	if ip := e.rewriteIP("www.github.com", true); ip == nil || ip.String() != "140.82.112.3" {
		t.Fatalf("suffix match failed: %v", ip)
	}
	if ip := e.rewriteIP("WWW.GitHub.com", true); ip == nil {
		t.Fatalf("case-insensitive lookup failed: %v", ip)
	}
	if ip := e.rewriteIP("notgithub.com", true); ip != nil {
		t.Fatalf("unrelated domain matched: %v", ip)
	}
}

func TestRewriteCNAMEIgnoresIPEntries(t *testing.T) {
	e := NewEngine()

	e.SetRewriteRules(`{"github.com": ["140.82.112.3", "2606:50c0:8000::153"]}`)

	if target := e.rewriteCNAME("github.com"); target != "" {
		t.Fatalf("cname lookup on IP entry = %q, want empty", target)
	}
}

func TestRewriteAnswerRecordFamilies(t *testing.T) {
	aQ := dns.Question{Name: "github.com.", Qtype: dns.TypeA, Qclass: dns.ClassINET}
	rr := rewriteAnswerRecord(aQ, net.ParseIP("140.82.112.3"))
	if a, ok := rr.(*dns.A); !ok || a.A.String() != "140.82.112.3" {
		t.Fatalf("A record = %v", rr)
	}
	aaaaQ := dns.Question{Name: "github.com.", Qtype: dns.TypeAAAA, Qclass: dns.ClassINET}
	rr6 := rewriteAnswerRecord(aaaaQ, net.ParseIP("2606:50c0:8000::153"))
	if aaaa, ok := rr6.(*dns.AAAA); !ok || aaaa.AAAA.String() != "2606:50c0:8000::153" {
		t.Fatalf("AAAA record = %v", rr6)
	}
}

func TestSetRewriteRulesClearsWithEmptyContent(t *testing.T) {
	e := NewEngine()

	e.SetRewriteRules(`{"github.com": "140.82.112.3"}`)
	if e.rewriteIP("github.com", true) == nil {
		t.Fatal("rule missing after first push")
	}
	e.SetRewriteRules("")
	if e.rewriteIP("github.com", true) != nil {
		t.Fatal("rule survived clearing")
	}
}

func parseResolveResult(t *testing.T, jsonStr string) resolveDomainResult {
	t.Helper()
	var result resolveDomainResult
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		t.Fatalf("invalid JSON from ResolveDomain: %v (%s)", err, jsonStr)
	}
	return result
}

func TestResolveDomainRewriteAnswer(t *testing.T) {
	e := NewEngine()

	e.SetRewriteRules(`{"github.com": "140.82.112.3"}`)

	result := parseResolveResult(t, e.ResolveDomain("github.com", true))
	if result.Error != "" || result.Source != "rewrite" || len(result.IPs) != 1 || result.IPs[0] != "140.82.112.3" {
		t.Fatalf("ResolveDomain = %+v, want rewrite 140.82.112.3", result)
	}

	// IPv6 queries fall through to the upstream path when only an IPv4
	// rewrite exists (same as the DNS pipeline), so without a resolver the
	// diagnostics result reports the inactive resolver.
	result6 := parseResolveResult(t, e.ResolveDomain("github.com", false))
	if result6.Error != "tunnel resolver not active" {
		t.Fatalf("ResolveDomain ipv6 = %+v, want resolver-not-active error", result6)
	}
}

func TestResolveDomainBlockedByPolicy(t *testing.T) {
	e := NewEngine()

	if err := e.policyEngine.applySnapshot(`{"filterEnabled":true,"globalBlock":["ads.example.com"]}`); err != nil {
		t.Fatalf("applySnapshot: %v", err)
	}

	result := parseResolveResult(t, e.ResolveDomain("ads.example.com", true))
	if result.Error != "" || result.Source != "blocked" || result.Reason != "ads.example.com" {
		t.Fatalf("ResolveDomain = %+v, want blocked by ads.example.com", result)
	}
}

func TestResolveDomainErrors(t *testing.T) {
	e := NewEngine()

	if result := parseResolveResult(t, e.ResolveDomain("  ", true)); result.Error == "" {
		t.Fatalf("ResolveDomain empty = %+v, want error", result)
	}

	result := parseResolveResult(t, e.ResolveDomain("github.com", true))
	if result.Error != "tunnel resolver not active" {
		t.Fatalf("ResolveDomain without resolver = %+v, want resolver-not-active error", result)
	}
}
