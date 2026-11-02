package tunnel

import (
	"encoding/json"
	"fmt"
	"testing"

	"github.com/miekg/dns"
)

// largePolicySnapshotJSON builds a synthetic rule set shaped like a heavy
// subscription load: many exact rules, thousands of wildcards (mostly the
// common "*.domain" form plus some infix globs) and a few special rules.
func largePolicySnapshotJSON(tb testing.TB) string {
	tb.Helper()
	var globalBlock, globalAllow []string
	for i := 0; i < 50000; i++ {
		globalBlock = append(globalBlock, fmt.Sprintf("ad%d.tracker%d.com", i, i%97))
	}
	for i := 0; i < 3000; i++ {
		globalBlock = append(globalBlock, fmt.Sprintf("*.wc%d.net", i))
	}
	for i := 0; i < 500; i++ {
		globalBlock = append(globalBlock, fmt.Sprintf("ads%d*.example.org", i))
	}
	for i := 0; i < 200; i++ {
		globalAllow = append(globalAllow, fmt.Sprintf("*.good%d.org", i))
	}
	var special []map[string]any
	for i := 0; i < 30; i++ {
		special = append(special, map[string]any{
			"pattern": fmt.Sprintf(`^banner%d\..*\.cn$`, i), "source": "rx", "isRegex": true,
		})
	}
	raw, err := json.Marshal(map[string]any{
		"filterEnabled": true,
		"globalBlock":   globalBlock,
		"globalAllow":   globalAllow,
		"specialBlock":  special,
		"appRules": map[string]any{
			"com.example.app": map[string]any{"block": []string{"*.appads.com", "x.appads.net"}},
		},
	})
	if err != nil {
		tb.Fatal(err)
	}
	return string(raw)
}

func benchmarkDomains() []string {
	domains := make([]string, 0, 1024)
	for i := 0; i < 1024; i++ {
		switch i % 4 {
		case 0:
			domains = append(domains, fmt.Sprintf("img%d.cdn.service%d.com", i, i))
		case 1:
			domains = append(domains, fmt.Sprintf("a.b.wc%d.net", i))
		case 2:
			domains = append(domains, fmt.Sprintf("ads%d-x.example.org", i%600))
		default:
			domains = append(domains, fmt.Sprintf("api.app%d.io", i))
		}
	}
	return domains
}

func BenchmarkPolicyEvaluateLargeHot(b *testing.B) {
	pe := newPolicyEngine()
	if err := pe.applySnapshot(largePolicySnapshotJSON(b)); err != nil {
		b.Fatal(err)
	}
	domains := benchmarkDomains()[:64]
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		pe.evaluate(domains[i%len(domains)], "", dns.TypeA)
	}
}

func BenchmarkPolicyEvaluateLargeCold(b *testing.B) {
	pe := newPolicyEngine()
	if err := pe.applySnapshot(largePolicySnapshotJSON(b)); err != nil {
		b.Fatal(err)
	}
	snap := pe.snapshot.Load()
	domains := benchmarkDomains()
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		snap.evaluateUncached(domains[i%len(domains)], "", dns.TypeA)
	}
}
