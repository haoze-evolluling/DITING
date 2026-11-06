// dns_cache.go is the Go face of the Rust DNS cache container.
//
// The sharded LRU, the TTL policy, the entry deadlines, the background sweeper, the counters and
// the snapshot projection live in rust/diting-dns-cache-core (see src/cache.rs). What stays here
// is what must run in Go: the single-flight coalescer around the resolver callback, the finalizer
// that releases the native handle, and the cached policy flags the engine reads before it calls
// the cache at all.
//
// The kernel is required: a missing library or a stale ABI leaves the cache disabled, so every
// lookup misses and every store is refused. Answers are then served straight from the resolver,
// which is exactly what the engine did before the cache existed.

package tunnel

import (
	"encoding/json"
	"runtime"
	"sync/atomic"
)

// dnsCacheHit is one answer read out of the cache. A stale hit carries the same fields; its wire
// is patched with a one second TTL.
type dnsCacheHit struct {
	wire         []byte
	chainTargets []chainTarget
	ipList       []string
	resolvedIPs  string
	isNegative   bool
	stale        bool
}

type dnsCache struct {
	handle *nativeDNSCacheHandle
	// flags mirrors the normalized booleans the kernel reports, so isEnabled and
	// isStaleFallbackEnabled cost one atomic load instead of a boundary call.
	flags  atomic.Uint32
	flight singleFlightGroup
	closed atomic.Bool
}

func newDNSCache(cfg dnsCacheConfig) *dnsCache {
	cache := &dnsCache{
		flight: singleFlightGroup{
			calls: make(map[string]*flightCall),
		},
	}
	handle, flags, err := newNativeDNSCache(cfg)
	if err != nil {
		// dnsCacheKernel logged the reason once per process; a cache without a handle misses
		// every lookup and refuses every store.
		return cache
	}
	cache.handle = handle
	cache.flags.Store(flags)
	// The handle is freed with the cache: a finalizer cannot run while a query is in flight, so
	// no goroutine can touch a released handle.
	runtime.SetFinalizer(cache, func(c *dnsCache) {
		if c.handle != nil {
			c.handle.free()
			c.handle = nil
		}
	})
	return cache
}

// updatePolicy normalizes and installs a new policy in the kernel. Switching the cache off
// releases its entries immediately; a rejected policy keeps the previous one.
func (c *dnsCache) updatePolicy(cfg dnsCacheConfig) {
	if c.handle == nil {
		return
	}
	flags, err := c.handle.updatePolicy(cfg)
	if err != nil {
		logf("dnsCache: policy update rejected: %v", err)
		return
	}
	c.flags.Store(flags)
}

func (c *dnsCache) isEnabled() bool {
	return c.flags.Load()&dnsCacheFlagEnabled != 0
}

func (c *dnsCache) isStaleFallbackEnabled() bool {
	return c.flags.Load()&(dnsCacheFlagEnabled|dnsCacheFlagStaleFallback) ==
		dnsCacheFlagEnabled|dnsCacheFlagStaleFallback
}

// close stops the kernel's background sweeper. Entries stay readable; the handle itself is
// released by the finalizer.
func (c *dnsCache) close() {
	if c.closed.Swap(true) {
		return
	}
	if c.handle != nil {
		c.handle.close()
	}
}

func (c *dnsCache) clear() {
	if c.handle != nil {
		c.handle.clear()
	}
}

// lookup returns the hit for rawQuery and whether it is a stale candidate.
//
// count == false is the single-flight re-check: the kernel then leaves the hit/miss counters
// alone, so each client query is counted once.
func (c *dnsCache) lookup(rawQuery []byte, count bool) (*dnsCacheHit, bool) {
	if c.handle == nil {
		return nil, false
	}
	hit, err := c.handle.lookup(rawQuery, count)
	if err != nil {
		logf("dnsCache: lookup failed: %v", err)
		return nil, false
	}
	if hit == nil {
		return nil, false
	}
	return hit, hit.stale
}

// getFast returns a fresh hit or a stale candidate, never both.
func (c *dnsCache) getFast(rawQuery []byte) (fresh *dnsCacheHit, stale *dnsCacheHit) {
	hit, isStale := c.lookup(rawQuery, true)
	if hit == nil {
		return nil, nil
	}
	if isStale {
		return nil, hit
	}
	return hit, nil
}

// get keeps the older three-value shape for the cache tests.
func (c *dnsCache) get(rawQuery []byte) (response []byte, hit bool, staleCandidate *dnsCacheHit) {
	fresh, stale := c.getFast(rawQuery)
	if fresh != nil {
		return fresh.wire, true, nil
	}
	return nil, false, stale
}

// beginStaleRefresh claims the one background refresh of a stale entry.
func (c *dnsCache) beginStaleRefresh(rawQuery []byte) bool {
	if c.handle == nil {
		return false
	}
	return c.handle.refreshBegin(rawQuery)
}

// endStaleRefresh releases the claim taken by beginStaleRefresh.
func (c *dnsCache) endStaleRefresh(rawQuery []byte) {
	if c.handle == nil {
		return
	}
	c.handle.refreshDone(rawQuery)
}

func (c *dnsCache) put(rawQuery, rawResponse []byte) bool {
	return c.putResponse(rawQuery, rawResponse)
}

// putResponse stores one answer. The kernel reads the response metadata straight from the wire,
// applies the TTL policy and keeps the upstream bytes verbatim for the next hit.
func (c *dnsCache) putResponse(rawQuery, rawResponse []byte) bool {
	if c.handle == nil {
		return false
	}
	return c.handle.put(rawQuery, rawResponse)
}

func (c *dnsCache) stats() dnsCacheStats {
	if c.handle != nil {
		if stats, err := c.handle.stats(); err == nil {
			return stats
		} else {
			logf("dnsCache: stats failed: %v", err)
		}
	}
	return dnsCacheStats{Enabled: c.isEnabled()}
}

func (c *dnsCache) statsJSON() string {
	b, err := json.Marshal(c.stats())
	if err != nil {
		return "{}"
	}
	return string(b)
}
