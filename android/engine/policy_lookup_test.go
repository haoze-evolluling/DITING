package tunnel

import (
	"fmt"
	"math/rand"
	"regexp"
	"testing"

	"github.com/miekg/dns"
)

// linearWildcardMatch is the pre-index behaviour: first matcher in list order.
func linearWildcardMatch(list []*wildcardMatcher, domain string) (string, bool) {
	for _, wc := range list {
		if wc.matches(domain) {
			return wc.pattern, true
		}
	}
	return "", false
}

func TestWildcardIndexMatchesLinearScan(t *testing.T) {
	patterns := []string{
		"*.example.com", "ads*.example.org", "*tracker.net", "foo.*.com", "*.foo.",
		"x*", "*-ad.*.cn", "*.b.com", "a*b.c.d", "*.example.com", "*.cn", "*ads",
		"*.xn--fiqs8s", "*.中国", "img*.cdn.*", "*.a..b",
	}
	labels := []string{"a", "b", "com", "example", "org", "ads1", "adsx", "net", "tracker",
		"mytracker", "foo", "cn", "x-ad", "c", "d", "axb", "img2", "cdn", "xn--fiqs8s", "中国", ""}
	rng := rand.New(rand.NewSource(1))
	for round := 0; round < 200; round++ {
		var list []*wildcardMatcher
		for _, p := range patterns {
			if rng.Intn(3) > 0 {
				list = append(list, newWildcardMatcher(p))
			}
		}
		rng.Shuffle(len(list), func(i, j int) { list[i], list[j] = list[j], list[i] })
		if round%50 == 0 {
			list = append(list, newWildcardMatcher("*"))
		}
		idx := newWildcardIndex(list)
		for n := 0; n < 300; n++ {
			parts := make([]string, 1+rng.Intn(4))
			for i := range parts {
				parts[i] = labels[rng.Intn(len(labels))]
			}
			domain := parts[0]
			for _, p := range parts[1:] {
				domain += "." + p
			}
			wantPat, wantHit := linearWildcardMatch(list, domain)
			gotPat, gotHit := idx.match(domain)
			if wantHit != gotHit || wantPat != gotPat {
				t.Fatalf("round %d domain %q: index=(%q,%v) linear=(%q,%v)", round, domain, gotPat, gotHit, wantPat, wantHit)
			}
		}
	}
}

func TestPolicyDecisionCacheTracksSnapshotReload(t *testing.T) {
	pe := newPolicyEngine()
	if err := pe.applySnapshot(`{"globalBlock":["*.ads.com"]}`); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if blocked, _ := pe.evaluate("x.ads.com", "", dns.TypeA); !blocked {
			t.Fatal("want blocked before reload")
		}
	}
	if err := pe.applySnapshot(`{"globalAllow":["x.ads.com"],"globalBlock":["*.ads.com"]}`); err != nil {
		t.Fatal(err)
	}
	if blocked, reason := pe.evaluate("X.Ads.com.", "", dns.TypeA); blocked || reason != "__ALLOW__" {
		t.Fatalf("after reload got (%v,%q), want allow", blocked, reason)
	}
}

func TestPolicyDecisionCacheKeepsAppAndQtypeApart(t *testing.T) {
	pe := newPolicyEngine()
	snapshot := `{
		"appRules": {"com.a": {"block": ["t.example.com"]}},
		"specialBlock": [{"pattern": "q.example.com", "source": "s", "dnsType": "AAAA"}]
	}`
	if err := pe.applySnapshot(snapshot); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if blocked, _ := pe.evaluate("t.example.com", "com.a", dns.TypeA); !blocked {
			t.Fatal("app rule should block com.a")
		}
		if blocked, _ := pe.evaluate("t.example.com", "com.b", dns.TypeA); blocked {
			t.Fatal("app rule must not leak to com.b via cache")
		}
		if blocked, _ := pe.evaluate("q.example.com", "", dns.TypeAAAA); !blocked {
			t.Fatal("dnsType rule should block AAAA")
		}
		if blocked, _ := pe.evaluate("q.example.com", "", dns.TypeA); blocked {
			t.Fatal("dnsType rule must not leak to A via cache")
		}
	}
}

func TestPolicyDecisionCacheEvictionAndPrewarm(t *testing.T) {
	pe := newPolicyEngine()
	if err := pe.applySnapshot(`{"globalBlock":["hot.com"]}`); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 20; i++ {
		pe.evaluate("hot.com", "", dns.TypeA)
	}
	for i := 0; i < decisionCacheShards*decisionCacheShardSize*2; i++ {
		pe.evaluate(fmt.Sprintf("d%d.example", i), "", dns.TypeA)
	}
	prev := pe.snapshot.Load()
	if _, _, ok := prev.cache.get(decisionKey{domain: "hot.com"}); !ok {
		t.Fatal("frequently used entry should survive CLOCK eviction")
	}
	next := &policySnapshot{filterEnabled: true, hasRules: true, globalAllow: map[string]struct{}{"hot.com": {}}}
	next.finalizeLookup()
	next.prewarmFrom(prev)
	blocked, reason, ok := next.cache.get(decisionKey{domain: "hot.com"})
	if !ok || blocked || reason != "__ALLOW__" {
		t.Fatalf("prewarmed entry = (%v,%q,%v), want fresh allow decision", blocked, reason, ok)
	}
}

func TestRegexAnchoredPrefixAgreesWithRegex(t *testing.T) {
	cases := []struct{ pattern, want string }{
		{`(?i)^banner7\..*\.cn$`, "banner7."},
		{`(?i)^ad[0-9]+\.`, "ad"},
		{`(?i)ads\.`, ""},
		{`(?i)^(ads|track)\.`, ""},
		{`(?i)^a|^b`, ""},
		{`(?i)^ab?c`, "a"},
	}
	domains := []string{"banner7.x.cn", "banner7x.cn", "ad12.com", "a.com", "ac.org", "abc.org", "b.org", "track.io", "ads.io"}
	for _, c := range cases {
		if got := regexAnchoredPrefix(c.pattern); got != c.want {
			t.Errorf("regexAnchoredPrefix(%q) = %q, want %q", c.pattern, got, c.want)
		}
		rx := regexp.MustCompile(c.pattern)
		prefix := regexAnchoredPrefix(c.pattern)
		for _, d := range domains {
			if rx.MatchString(d) && !mayMatchPrefix(d, prefix) {
				t.Errorf("prefilter %q rejected %q, which %q matches", prefix, d, c.pattern)
			}
		}
	}
}
