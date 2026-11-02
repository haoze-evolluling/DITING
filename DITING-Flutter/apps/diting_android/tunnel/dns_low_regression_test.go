// dns_low_regression_test.go covers the Low-severity triage items that live in
// the Go tunnel: UDP truncation handling (A-019), dnsCache.clear() orphan
// re-linking (A-069), the unbounded cert
// cache (A-071), the connLogSeen dedupe set bound (A-073), ApplyDNSConfig
// partial-application (A-090) and the InjectingReader carry flush at EOF (A-064).

package tunnel

import (
	"crypto/tls"
	"encoding/json"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// --- A-019: truncated UDP responses -----------------------------------------

func TestIsTruncatedResponse(t *testing.T) {
	query := new(dns.Msg)
	query.SetQuestion("example.com.", dns.TypeA)
	raw, err := query.Pack()
	if err != nil {
		t.Fatal(err)
	}

	if isTruncatedResponse(raw) {
		t.Fatalf("a plain query must not be reported as truncated")
	}
	if isTruncatedResponse(nil) || isTruncatedResponse(raw[:11]) {
		t.Fatalf("short buffers must not be reported as truncated")
	}

	truncated := append([]byte(nil), raw...)
	truncated[2] |= 0x02 // TC is bit 1 of the high flags byte
	if !isTruncatedResponse(truncated) {
		t.Fatalf("TC flag was not detected")
	}
	// The same bit position must not collide with QR (0x80) / AA (0x04).
	otherFlags := append([]byte(nil), raw...)
	otherFlags[2] = 0x84 // QR + AA
	if isTruncatedResponse(otherFlags) {
		t.Fatalf("QR/AA bits must not be read as TC")
	}
}

// A truncated answer carries no complete records and must never enter the cache,
// otherwise the TC=1 header is replayed to every later client.
func TestDNSCacheRejectsTruncatedResponses(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true})
	defer cache.close()

	query := new(dns.Msg)
	query.SetQuestion("truncated.example.", dns.TypeA)
	rawQuery, err := query.Pack()
	if err != nil {
		t.Fatal(err)
	}

	resp := new(dns.Msg)
	resp.SetReply(query)
	resp.Truncated = true
	rawResp, err := resp.Pack()
	if err != nil {
		t.Fatal(err)
	}

	if cache.put(rawQuery, rawResp) {
		t.Fatalf("a truncated response must not be cached")
	}
	if _, hit, _ := cache.get(rawQuery); hit {
		t.Fatalf("truncated response was served from the cache")
	}
}

// --- A-069: dnsCache.clear() must not leave re-linkable orphans --------------

func TestDNSCacheClearUnlinksLruElements(t *testing.T) {
	cache := newDNSCache(dnsCacheConfig{Enabled: true})
	defer cache.close()

	query := new(dns.Msg)
	query.SetQuestion("clear.example.", dns.TypeA)
	rawQuery, err := query.Pack()
	if err != nil {
		t.Fatal(err)
	}
	resp := new(dns.Msg)
	resp.SetReply(query)
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: "clear.example.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
		A:   net.IPv4(1, 2, 3, 4),
	})
	rawResp, err := resp.Pack()
	if err != nil {
		t.Fatal(err)
	}
	if !cache.put(rawQuery, rawResp) {
		t.Fatal("put failed")
	}

	shard := cache.shard(cacheKey("clear.example", dns.TypeA, dns.ClassINET))
	shard.mu.Lock()
	entry := shard.entries[cacheKey("clear.example", dns.TypeA, dns.ClassINET)]
	if entry == nil || entry.elem == nil {
		shard.mu.Unlock()
		t.Fatal("entry/elem missing before clear")
	}
	staleElem := entry.elem
	shard.mu.Unlock()

	cache.clear()

	shard.mu.Lock()
	lruLen := shard.lruList.Len()
	entriesLen := len(shard.entries)
	shard.mu.Unlock()
	if lruLen != 0 || entriesLen != 0 {
		t.Fatalf("clear left state behind: lru=%d entries=%d", lruLen, entriesLen)
	}

	// Walk the list instead of trusting Len(): Init() resets the List's len field
	// but every Element keeps a live `list` back-pointer, so a racing promotion
	// re-splices the orphan in *without* incrementing len. A later PushFront then
	// yields a list whose Len() is 1 while iteration actually visits 2 nodes,
	// permanently desynchronising the LRU from the entries map.
	shard.mu.Lock()
	shard.lruList.MoveToFront(staleElem) // a no-op only if the element was removed
	shard.lruList.PushFront(&cacheEntry{key: "fresh"})
	reached := 0
	for e := shard.lruList.Front(); e != nil && reached < 100; e = e.Next() {
		reached++
	}
	shard.mu.Unlock()
	if reached != 1 {
		t.Fatalf("cleared LRU iterates over %d nodes, want 1 (orphan was re-linked)", reached)
	}
}

// --- A-071: bounded certificate cache --------------------------------------

func TestCertCacheStoreIsBounded(t *testing.T) {
	var store certCacheStore
	store.reset(4)

	for i := 0; i < 10; i++ {
		store.store(string(rune('a'+i)), &cachedCert{
			cert:      &testingCertStub,
			expiresAt: time.Now().Add(time.Hour),
		})
	}
	if got := store.len(); got != 4 {
		t.Fatalf("cache size = %d, want 4", got)
	}

	// The most recent entries survive, the oldest were evicted.
	if _, ok := store.load("j"); !ok {
		t.Fatalf("most recent entry was evicted")
	}
	if _, ok := store.load("a"); ok {
		t.Fatalf("oldest entry survived eviction")
	}
}

func TestCertCacheStoreDropsExpiredEntries(t *testing.T) {
	var store certCacheStore
	store.reset(8)
	store.store("fresh.example", &cachedCert{
		cert:      &testingCertStub,
		expiresAt: time.Now().Add(time.Hour),
	})
	store.store("stale.example", &cachedCert{
		cert:      &testingCertStub,
		expiresAt: time.Now().Add(time.Minute),
	})

	store.purgeExpired(time.Now())

	if _, ok := store.load("fresh.example"); !ok {
		t.Fatalf("fresh entry was purged")
	}
	if _, ok := store.load("stale.example"); ok {
		t.Fatalf("entry inside the 5-minute renewal margin survived")
	}
}

func TestCertCacheStoreDeleteAndReset(t *testing.T) {
	var store certCacheStore
	store.reset(8)
	store.store("a.example", &cachedCert{cert: &testingCertStub, expiresAt: time.Now().Add(time.Hour)})
	store.delete("a.example")
	if store.len() != 0 {
		t.Fatalf("delete left %d entries", store.len())
	}
	store.delete("missing.example") // must not panic
	store.store("b.example", &cachedCert{cert: &testingCertStub, expiresAt: time.Now().Add(time.Hour)})
	store.reset(8)
	if store.len() != 0 {
		t.Fatalf("reset left %d entries", store.len())
	}
}

// --- A-073: bounded connLogSeen -------------------------------------------

func TestConnLogSeenDedupIsBounded(t *testing.T) {
	var dedup connLogSeenDedup
	dedup.reset()

	if dedup.markSeen("k1") {
		t.Fatalf("first sighting reported as duplicate")
	}
	if !dedup.markSeen("k1") {
		t.Fatalf("second sighting not reported as duplicate")
	}

	for i := 0; i < connLogSeenMaxEntries+50; i++ {
		dedup.markSeen(string(rune('A'+i%26)) + string(rune(0x1000+i)))
	}
	if got := dedup.size(); got > connLogSeenMaxEntries {
		t.Fatalf("dedupe set grew past the bound: %d", got)
	}
	if dedup.cleared.Load() == 0 {
		t.Fatalf("overflow reset never fired")
	}

	dedup.reset()
	if dedup.size() != 0 {
		t.Fatalf("reset left %d entries", dedup.size())
	}
}

// --- A-064: InjectingReader must flush carry at EOF ------------------------

func TestInjectingReaderFlushesPartialHeadAtEOF(t *testing.T) {
	// The document ends in a bare `<head` with no `>`. The reader parks it in
	// carry hoping the next read completes the tag; at EOF those bytes are still
	// part of the document and used to be dropped.
	const body = "<html><body><head"
	got, err := io.ReadAll(NewInjectingReader(strings.NewReader(body), "example.com"))
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if string(got) != body {
		t.Fatalf("carry was dropped at EOF: got %q, want %q", string(got), body)
	}
}

func TestInjectingReaderInjectsWhenHeadIsComplete(t *testing.T) {
	const body = "<html><head><title>t</title></head><body>x</body></html>"
	out, err := io.ReadAll(NewInjectingReader(strings.NewReader(body), "example.com"))
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if !strings.Contains(string(out), `rel="stylesheet"`) {
		t.Fatalf("stylesheet link was not injected: %q", string(out))
	}
	if !strings.Contains(string(out), "<title>t</title>") {
		t.Fatalf("document body was damaged: %q", string(out))
	}
}

func TestInjectingReaderPassthroughWhenNoHead(t *testing.T) {
	const body = "<html><body>no head here at all</body></html>"
	out, err := io.ReadAll(NewInjectingReader(strings.NewReader(body), "example.com"))
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if string(out) != body {
		t.Fatalf("document was altered: got %q, want %q", string(out), body)
	}
}

// --- A-090: ApplyDNSConfig must not partially apply a rejected snapshot -----

func TestApplyDNSConfigDoesNotPartiallyApply(t *testing.T) {
	engine := NewEngine()
	defer engine.Stop()

	// Establish a known baseline.
	good := map[string]any{
		"mode":          "single",
		"blockResponse": "NXDOMAIN",
		"providers": []map[string]any{
			{"id": "p1", "protocol": "PLAIN", "server": "1.1.1.1:53"},
		},
	}
	goodJSON, _ := json.Marshal(good)
	if err := engine.ApplyDNSConfig(string(goodJSON)); err != nil {
		t.Fatalf("baseline config rejected: %v", err)
	}
	if got := engine.blockResponseType(); got != ResponseNXDomain {
		t.Fatalf("baseline block response = %v", got)
	}

	// Rejected snapshot: valid blockResponse, invalid provider.
	bad := map[string]any{
		"mode":          "single",
		"blockResponse": "REFUSED",
		"providers": []map[string]any{
			{"id": "p1", "protocol": "NOT_A_PROTOCOL", "server": "1.1.1.1:53"},
		},
	}
	badJSON, _ := json.Marshal(bad)
	if err := engine.ApplyDNSConfig(string(badJSON)); err == nil {
		t.Fatalf("invalid provider was accepted")
	}

	if got := engine.blockResponseType(); got != ResponseNXDomain {
		t.Fatalf("rejected snapshot changed the block mode: %v", got)
	}
}

func TestApplyDNSConfigRejectsNoProviders(t *testing.T) {
	engine := NewEngine()
	defer engine.Stop()

	cfg := map[string]any{"mode": "single", "blockResponse": "REFUSED", "providers": []any{}}
	raw, _ := json.Marshal(cfg)
	if err := engine.ApplyDNSConfig(string(raw)); err == nil {
		t.Fatalf("empty provider list was accepted")
	}
	if got := engine.blockResponseType(); got != ResponseCustomIP {
		t.Fatalf("rejected snapshot changed the default block mode: %v", got)
	}
}

// testingCertStub is a placeholder certificate value for cache-behaviour tests
// that never hand the entry to a TLS stack.
var testingCertStub = tls.Certificate{}
