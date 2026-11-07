//go:build cgo

// ip_domain_cache_test.go pins the Go boundary of the Rust IP → domain LRU: in-place update,
// eviction of the least-recently-written entry (a read never promotes), empty keys, and the
// no-kernel fallback.

package tunnel

import "testing"

func TestIPDomainCacheBasicAndEmptyKeys(t *testing.T) {
	cache := newIPDomainCache(4)
	cache.put("203.0.113.1", "one.example")
	if got := cache.get("203.0.113.1"); got != "one.example" {
		t.Fatalf("get = %q, want one.example", got)
	}
	if got := cache.get("203.0.113.2"); got != "" {
		t.Fatalf("missing key = %q, want empty", got)
	}
	cache.put("", "ignored.example")
	cache.put("203.0.113.3", "")
	if got := cache.size(); got != 1 {
		t.Fatalf("size = %d, want 1", got)
	}
}

func TestIPDomainCacheUpdateAndReadDoNotPromote(t *testing.T) {
	cache := newIPDomainCache(2)
	cache.put("a", "1")
	cache.put("b", "2")
	// A read must not promote `a`; the next insert still evicts it.
	if got := cache.get("a"); got != "1" {
		t.Fatalf("get a = %q", got)
	}
	cache.put("c", "3")
	if got := cache.get("a"); got != "" {
		t.Fatalf("a should have been evicted, got %q", got)
	}

	// A put of an existing key updates in place and moves it to the front.
	cache.put("b", "2-updated")
	if got := cache.get("b"); got != "2-updated" {
		t.Fatalf("get b = %q, want 2-updated", got)
	}
	cache.put("d", "4")
	if got := cache.get("c"); got != "" {
		t.Fatalf("c should have been evicted, got %q", got)
	}
	if got := cache.get("b"); got != "2-updated" {
		t.Fatalf("b should have survived, got %q", got)
	}
}

func TestIPDomainCacheWithoutKernelDisablesHints(t *testing.T) {
	cache := &ipDomainCache{}
	cache.put("203.0.113.1", "one.example")
	if got := cache.get("203.0.113.1"); got != "" {
		t.Fatalf("a cache without a kernel must miss, got %q", got)
	}
	if got := cache.size(); got != 0 {
		t.Fatalf("size = %d, want 0", got)
	}
}
