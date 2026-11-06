package tunnel

import (
	"strings"
	"testing"

	"github.com/miekg/dns"
)

// The key is the documented "name:qtype:qclass" form: lowercased, labels joined
// with '.', no trailing dot. put and lookup both go through the Rust kernel, so a
// format change would only show up as permanent misses without this test.
func TestQuestionKeyFormat(t *testing.T) {
	cases := []struct {
		name  string
		qtype uint16
		want  string
	}{
		{"Example.COM.", dns.TypeAAAA, "example.com:28:1"},
		{"a.b.c.d.example.org.", dns.TypeA, "a.b.c.d.example.org:1:1"},
		{".", dns.TypeA, ":1:1"},
	}
	for _, tc := range cases {
		q := new(dns.Msg)
		q.SetQuestion(tc.name, tc.qtype)
		raw, err := q.Pack()
		if err != nil {
			t.Fatal(err)
		}
		var buf [maxCacheKeyLen]byte
		key, nameLen, qtype, qclass, ok := nativeQuestionKey(raw, buf[:])
		if !ok {
			t.Fatalf("%q: key build failed", tc.name)
		}
		if string(key) != tc.want {
			t.Fatalf("%q: key %q, want %q", tc.name, key, tc.want)
		}
		if got, want := string(key[:nameLen]), strings.TrimSuffix(strings.ToLower(tc.name), "."); got != want {
			t.Fatalf("%q: name part %q, want %q", tc.name, got, want)
		}
		if qtype != tc.qtype || qclass != dns.ClassINET {
			t.Fatalf("%q: parsed (%d,%d)", tc.name, qtype, qclass)
		}
	}

	// A destination buffer that cannot hold the key is refused rather than truncated.
	q := new(dns.Msg)
	q.SetQuestion("example.com.", dns.TypeA)
	raw, err := q.Pack()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, _, _, ok := nativeQuestionKey(raw, make([]byte, 4)); ok {
		t.Fatal("a too-small key buffer must be rejected")
	}
	if _, _, _, _, ok := nativeQuestionKey([]byte{0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 'a'}, make([]byte, maxCacheKeyLen)); ok {
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
