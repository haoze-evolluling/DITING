// dns_cache.go implements a thread-safe, high-performance sharded in-memory DNS response cache.
//
// Modular Architecture:
// - dns_cache.go: Core cache coordination, sharding, LRU operations, get/put, and telemetry.
// - dns_cache_types.go: Data structures, configuration, entry models, and shard structures.
// - dns_cache_wire.go: Zero-copy DNS wire-format parsing, TTL offset indexing, and metadata extraction.
// - dns_cache_policy.go: Policy normalization, TTL evaluation (RFC 2181 / RFC 2308), and active expiration.
// - dns_cache_flight.go: Panic-safe single-flight concurrent query coalescing.

package tunnel

import (
	"container/list"
	"encoding/json"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

type dnsCache struct {
	configMu   sync.RWMutex
	config     dnsCacheConfig
	shards     [numDNSCacheShards]*cacheShard
	maxEntries int

	flight singleFlightGroup

	totalHits    atomic.Uint64
	totalMisses  atomic.Uint64
	staleHits    atomic.Uint64
	negativeHits atomic.Uint64
	evictions    atomic.Uint64

	stopCleaner chan struct{}
	closed      atomic.Bool
}

func newDNSCache(cfg dnsCacheConfig) *dnsCache {
	normalizeDNSCacheConfig(&cfg)

	maxEntries := defaultMaxCacheEntries
	entriesPerShard := maxEntries / numDNSCacheShards
	if entriesPerShard <= 0 {
		entriesPerShard = 1
	}

	cache := &dnsCache{
		config:      cfg,
		maxEntries:  maxEntries,
		stopCleaner: make(chan struct{}),
		flight: singleFlightGroup{
			calls: make(map[string]*flightCall),
		},
	}

	for i := 0; i < numDNSCacheShards; i++ {
		cache.shards[i] = &cacheShard{
			entries:    make(map[string]*cacheEntry, entriesPerShard),
			lruList:    list.New(),
			maxEntries: entriesPerShard,
		}
	}

	cache.startCleaner()
	return cache
}

func (c *dnsCache) updatePolicy(cfg dnsCacheConfig) {
	normalizeDNSCacheConfig(&cfg)
	c.configMu.Lock()
	c.config = cfg
	c.configMu.Unlock()
}

func (c *dnsCache) getConfig() dnsCacheConfig {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config
}

func (c *dnsCache) isEnabled() bool {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled
}

func (c *dnsCache) isStaleFallbackEnabled() bool {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled && c.config.StaleFallbackEnabled
}

func (c *dnsCache) isNegativeCacheEnabled() bool {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled && c.config.NegativeTTLEnabled
}

func (c *dnsCache) close() {
	if c.closed.Swap(true) {
		return
	}
	close(c.stopCleaner)
}

func (c *dnsCache) clear() {
	for _, shard := range c.shards {
		shard.mu.Lock()
		for _, e := range shard.entries {
			if e != nil {
				e.elem = nil
			}
		}
		shard.entries = make(map[string]*cacheEntry, shard.maxEntries)
		shard.lruList.Init()
		shard.mu.Unlock()
	}
}

func (c *dnsCache) shard(key string) *cacheShard {
	return c.shards[fnv32(key)%numDNSCacheShards]
}

func (c *dnsCache) getEntry(key string) *cacheEntry {
	shard := c.shard(key)
	shard.mu.RLock()
	defer shard.mu.RUnlock()
	return shard.entries[key]
}

// getFast is the zero-copy fast path used by engine_dns.go.
// Returns patched wire bytes, hit status, pre-indexed CNAME targets, pre-extracted IPs, negative flag, and stale candidate.
func (c *dnsCache) getFast(rawQuery []byte) (response []byte, hit bool, targets []chainTarget, ipList []string, resolvedIPs string, isNegative bool, staleCandidate *cacheEntry) {
	cfg := c.getConfig()
	if !cfg.Enabled {
		return nil, false, nil, nil, "", false, nil
	}

	domain, qtype, qclass, queryID, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		return nil, false, nil, nil, "", false, nil
	}

	key := cacheKey(domain, qtype, qclass)
	now := time.Now()
	shard := c.shard(key)

	shard.mu.RLock()
	entry, exists := shard.entries[key]
	if !exists || entry == nil {
		shard.mu.RUnlock()
		c.totalMisses.Add(1)
		return nil, false, nil, nil, "", false, nil
	}

	// Case 1: Fresh Cache Hit
	if now.Before(entry.expiresAt) {
		remaining := entry.expiresAt.Sub(now)
		remainingSec := uint32(remaining.Seconds())
		if remainingSec == 0 {
			remainingSec = 1
		}

		entry.hitCount.Add(1)
		entry.lastHitAt.Store(now.UnixNano())
		c.totalHits.Add(1)
		if entry.isNegative {
			c.negativeHits.Add(1)
		}

		patched := patchWireResponse(entry.wire, entry.ttlOffsets, queryID, remainingSec)
		entryTargets := entry.chainTargets
		entryIPs := entry.ipList
		entryResolved := entry.resolvedIPs
		entryNeg := entry.isNegative
		elem := entry.elem
		shard.mu.RUnlock()

		// LRU promotion on hit (promotes if not already at the front)
		if elem != nil && shard.lruList.Front() != elem {
			shard.mu.Lock()
			if elem.Value != nil && shard.lruList.Front() != elem {
				shard.lruList.MoveToFront(elem)
			}
			shard.mu.Unlock()
		}

		return patched, true, entryTargets, entryIPs, entryResolved, entryNeg, nil
	}

	// Case 2: Stale Hit candidate
	if cfg.StaleFallbackEnabled && now.Before(entry.staleUntil) {
		shard.mu.RUnlock()
		return nil, false, entry.chainTargets, entry.ipList, entry.resolvedIPs, entry.isNegative, entry
	}

	shard.mu.RUnlock()

	// Case 3: Completely expired - lazy eviction
	shard.mu.Lock()
	if e, ok := shard.entries[key]; ok && e == entry && now.After(e.staleUntil) {
		delete(shard.entries, key)
		if e.elem != nil {
			shard.lruList.Remove(e.elem)
			e.elem = nil
		}
	}
	shard.mu.Unlock()

	c.totalMisses.Add(1)
	return nil, false, nil, nil, "", false, nil
}

// get maintains backwards compatibility with standard signature.
func (c *dnsCache) get(rawQuery []byte) (response []byte, hit bool, staleCandidate *cacheEntry) {
	resp, hit, _, _, _, _, stale := c.getFast(rawQuery)
	return resp, hit, stale
}

func (c *dnsCache) buildStaleResponse(rawQuery []byte, entry *cacheEntry) []byte {
	if entry == nil || len(entry.wire) < 12 {
		return nil
	}
	_, _, _, queryID, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		return nil
	}
	c.staleHits.Add(1)
	return patchWireResponse(entry.wire, entry.ttlOffsets, queryID, 1)
}

func (c *dnsCache) put(rawQuery, rawResponse []byte) bool {
	var respMsg dns.Msg
	if err := respMsg.Unpack(rawResponse); err != nil {
		return false
	}
	return c.putMsg(rawQuery, rawResponse, &respMsg)
}

func (c *dnsCache) putMsg(rawQuery, rawResponse []byte, respMsg *dns.Msg) bool {
	if respMsg == nil || len(rawResponse) < 12 {
		return false
	}
	cfg := c.getConfig()
	if !cfg.Enabled {
		return false
	}

	domain, qtype, qclass, _, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		return false
	}

	minTTL, found := extractMinTTL(respMsg)
	var effectiveTTL time.Duration
	isNegative := false

	if respMsg.Rcode == dns.RcodeNameError || (respMsg.Rcode == dns.RcodeSuccess && len(respMsg.Answer) == 0) {
		if !cfg.NegativeTTLEnabled {
			return false
		}
		isNegative = true
		effectiveTTL = c.calculateNegativeTTL(minTTL, found, cfg)
	} else if respMsg.Rcode == dns.RcodeSuccess && len(respMsg.Answer) > 0 {
		effectiveTTL = c.calculateEffectiveTTL(minTTL, cfg)
	} else {
		return false
	}

	if effectiveTTL <= 0 {
		return false
	}

	now := time.Now()
	expiresAt := now.Add(effectiveTTL)
	staleUntil := expiresAt
	if cfg.StaleFallbackEnabled && cfg.StaleFallbackSeconds > 0 {
		staleUntil = expiresAt.Add(time.Duration(cfg.StaleFallbackSeconds) * time.Second)
	}

	ttlOffsets := extractTtlOffsetsFromWire(rawResponse, isNegative)
	chainTargets := extractChainTargetsFromMsg(respMsg)
	ipList, resolvedIPs := extractIPsFromMsg(respMsg)

	wireCopy := make([]byte, len(rawResponse))
	copy(wireCopy, rawResponse)

	key := cacheKey(domain, qtype, qclass)
	entry := &cacheEntry{
		key:          key,
		domain:       domain,
		qtype:        qtype,
		qclass:       qclass,
		wire:         wireCopy,
		ttlOffsets:   ttlOffsets,
		originalTTL:  minTTL,
		effectiveTTL: effectiveTTL,
		createdAt:    now,
		expiresAt:    expiresAt,
		staleUntil:   staleUntil,
		isNegative:   isNegative,
		rcode:        respMsg.Rcode,
		chainTargets: chainTargets,
		ipList:       ipList,
		resolvedIPs:  resolvedIPs,
	}
	entry.lastHitAt.Store(now.UnixNano())

	shard := c.shard(key)
	shard.mu.Lock()
	defer shard.mu.Unlock()

	if old, exists := shard.entries[key]; exists {
		if old.elem != nil {
			shard.lruList.Remove(old.elem)
			old.elem = nil
		}
		delete(shard.entries, key)
	} else if len(shard.entries) >= shard.maxEntries {
		back := shard.lruList.Back()
		if back != nil {
			oldest := back.Value.(*cacheEntry)
			shard.lruList.Remove(back)
			if oldest != nil {
				oldest.elem = nil
				delete(shard.entries, oldest.key)
				c.evictions.Add(1)
			}
		}
	}

	entry.elem = shard.lruList.PushFront(entry)
	shard.entries[key] = entry
	return true
}

func (c *dnsCache) stats() dnsCacheStats {
	hits := c.totalHits.Load()
	misses := c.totalMisses.Load()
	total := hits + misses
	ratio := 0.0
	if total > 0 {
		ratio = float64(hits) / float64(total)
	}

	count := 0
	for _, shard := range c.shards {
		shard.mu.RLock()
		count += len(shard.entries)
		shard.mu.RUnlock()
	}

	return dnsCacheStats{
		Enabled:       c.isEnabled(),
		TotalHits:     hits,
		TotalMisses:   misses,
		StaleHits:     c.staleHits.Load(),
		NegativeHits:  c.negativeHits.Load(),
		HitRatio:      ratio,
		EntryCount:    count,
		MaxEntries:    c.maxEntries,
		EvictionCount: c.evictions.Load(),
	}
}

func (c *dnsCache) statsJSON() string {
	st := c.stats()
	b, err := json.Marshal(st)
	if err != nil {
		return "{}"
	}
	return string(b)
}
