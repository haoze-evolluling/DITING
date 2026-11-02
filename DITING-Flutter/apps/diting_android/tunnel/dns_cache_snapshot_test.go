// dns_cache_snapshot_test.go covers the JSON projection the Android layer mirrors
// into the `dns_cache` table: expiry filtering, hot-first ordering and the cap.

package tunnel

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func putCacheEntry(t *testing.T, cache *dnsCache, domain string, ttl uint32, hits int) {
	t.Helper()
	query := new(dns.Msg)
	query.SetQuestion(domain, dns.TypeA)
	rawQuery, err := query.Pack()
	if err != nil {
		t.Fatalf("pack query: %v", err)
	}

	resp := new(dns.Msg)
	resp.SetReply(query)
	rr, err := dns.NewRR(fmt.Sprintf("%s %d IN A 93.184.216.34", domain, ttl))
	if err != nil {
		t.Fatalf("build answer: %v", err)
	}
	resp.Answer = append(resp.Answer, rr)
	rawResp, err := resp.Pack()
	if err != nil {
		t.Fatalf("pack response: %v", err)
	}
	if !cache.put(rawQuery, rawResp) {
		t.Fatalf("expected put to succeed for %s", domain)
	}
	for i := 0; i < hits; i++ {
		cache.getFast(rawQuery)
	}
}

func TestDNSCacheSnapshotOrdersByHits(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true, Mode: "follow_dns_ttl", MaxTTLSeconds: 3600})
	defer cache.close()

	putCacheEntry(t, cache, "cold.example.com.", 300, 1)
	putCacheEntry(t, cache, "hot.example.com.", 300, 5)

	entries := cache.snapshot(time.Now(), 10)
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].QueryName != "hot.example.com" {
		t.Errorf("expected hottest entry first, got %q", entries[0].QueryName)
	}
	if entries[0].HitCount != 5 {
		t.Errorf("expected 5 hits, got %d", entries[0].HitCount)
	}
	if entries[0].ResponseSize == 0 {
		t.Error("expected a non-zero response size so the UI can show it")
	}
}

func TestDNSCacheSnapshotHonoursLimitAndExpiry(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true, Mode: "follow_dns_ttl", MaxTTLSeconds: 3600})
	defer cache.close()

	putCacheEntry(t, cache, "one.example.com.", 300, 3)
	putCacheEntry(t, cache, "two.example.com.", 300, 2)

	if got := cache.snapshot(time.Now(), 1); len(got) != 1 {
		t.Fatalf("expected the limit to cap the snapshot, got %d entries", len(got))
	}

	// A future "now" is past every TTL, so the projection must be empty: the engine can no
	// longer serve those answers and the repository filters them out anyway.
	if got := cache.snapshot(time.Now().Add(time.Hour), 10); len(got) != 0 {
		t.Fatalf("expected expired entries to be skipped, got %d", len(got))
	}
}

func TestEngineGetDNSCacheEntriesJSON(t *testing.T) {
	var nilEngine *Engine
	if got := nilEngine.GetDNSCacheEntries(10); got != "[]" {
		t.Errorf("expected empty JSON for a nil engine, got %q", got)
	}

	engine := &Engine{dnsCache: newDNSCache(dnsCacheConfig{
		Enabled:       true,
		Mode:          "follow_dns_ttl",
		MaxTTLSeconds: 3600,
	})}
	defer engine.dnsCache.close()

	putCacheEntry(t, engine.dnsCache, "engine.example.com.", 300, 2)

	var decoded []dnsCacheEntrySnapshot
	if err := json.Unmarshal([]byte(engine.GetDNSCacheEntries(10)), &decoded); err != nil {
		t.Fatalf("expected valid JSON, got %v", err)
	}
	if len(decoded) != 1 || decoded[0].QueryName != "engine.example.com" {
		t.Fatalf("unexpected snapshot: %+v", decoded)
	}
	if decoded[0].LastHitAt == 0 {
		t.Error("expected lastHitAt to be populated after a hit")
	}
}
