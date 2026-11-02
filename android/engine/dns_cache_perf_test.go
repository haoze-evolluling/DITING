package tunnel

import (
	"testing"

	"github.com/miekg/dns"
)

// The wire-built key must match cacheKey exactly, including case folding and
// compression pointers, or entries written by put would never be found.
func TestAppendQuestionKeyMatchesCacheKey(t *testing.T) {
	for _, name := range []string{"Example.COM.", "a.b.c.d.example.org.", "."} {
		q := new(dns.Msg)
		q.SetQuestion(name, dns.TypeAAAA)
		raw, err := q.Pack()
		if err != nil {
			t.Fatal(err)
		}
		key, nameLen, ok := appendQuestionKey(nil, raw)
		if !ok {
			t.Fatalf("%q: key build failed", name)
		}
		if want := cacheKey(name, dns.TypeAAAA, dns.ClassINET); string(key) != want {
			t.Fatalf("%q: key %q, want %q", name, key, want)
		}
		domain, qtype, qclass := parseKeyQuestion(string(key), nameLen)
		if domain+":28:1" != string(key) || qtype != dns.TypeAAAA || qclass != dns.ClassINET {
			t.Fatalf("%q: parsed (%q,%d,%d)", name, domain, qtype, qclass)
		}
	}
	if _, _, ok := appendQuestionKey(nil, []byte{0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 'a'}); ok {
		t.Fatal("truncated question must be rejected")
	}
}

// A miss followed by the single-flight re-check is one client query and must
// count as one miss, otherwise the reported hit ratio is skewed low.
func TestSingleFlightRecheckDoesNotDoubleCountMiss(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true, Mode: "follow_dns_ttl"})
	defer cache.close()

	q := new(dns.Msg)
	q.SetQuestion("once.example.", dns.TypeA)
	raw, _ := q.Pack()
	resp := new(dns.Msg)
	resp.SetReply(q)
	rr, _ := dns.NewRR("once.example. 300 IN A 192.0.2.1")
	resp.Answer = append(resp.Answer, rr)
	rawResp, _ := resp.Pack()

	if _, hit, _ := cache.get(raw); hit {
		t.Fatal("unexpected hit on empty cache")
	}
	if _, _, err := cache.singleFlight(raw, func() ([]byte, error) { return rawResp, nil }); err != nil {
		t.Fatal(err)
	}
	if _, hit, _ := cache.get(raw); !hit {
		t.Fatal("expected hit after resolve")
	}
	st := cache.stats()
	if st.TotalMisses != 1 || st.TotalHits != 1 {
		t.Fatalf("misses=%d hits=%d, want 1 and 1", st.TotalMisses, st.TotalHits)
	}
}

func TestDisablingCacheReleasesEntries(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true, Mode: "follow_dns_ttl"})
	defer cache.close()

	q := new(dns.Msg)
	q.SetQuestion("off.example.", dns.TypeA)
	raw, _ := q.Pack()
	resp := new(dns.Msg)
	resp.SetReply(q)
	rr, _ := dns.NewRR("off.example. 300 IN A 192.0.2.2")
	resp.Answer = append(resp.Answer, rr)
	rawResp, _ := resp.Pack()
	cache.put(raw, rawResp)

	cache.updatePolicy(dnsCacheConfig{Enabled: false})
	if n := cache.stats().EntryCount; n != 0 {
		t.Fatalf("entries after disable = %d, want 0", n)
	}
}
