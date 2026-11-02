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
	"encoding/binary"
	"encoding/json"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

type dnsCache struct {
	// config is swapped atomically: the hit path reads it once per query
	// without touching a lock shared by every DNS goroutine.
	config     atomic.Pointer[dnsCacheConfig]
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

	cache.config.Store(&cfg)
	cache.startCleaner()
	return cache
}

func (c *dnsCache) updatePolicy(cfg dnsCacheConfig) {
	normalizeDNSCacheConfig(&cfg)
	prev := c.config.Swap(&cfg)
	// A disabled cache is never read, so release its memory right away.
	if prev != nil && prev.Enabled && !cfg.Enabled {
		c.clear()
	}
}

func (c *dnsCache) getConfig() dnsCacheConfig {
	return *c.config.Load()
}

func (c *dnsCache) isEnabled() bool {
	return c.config.Load().Enabled
}

func (c *dnsCache) isStaleFallbackEnabled() bool {
	cfg := c.config.Load()
	return cfg.Enabled && cfg.StaleFallbackEnabled
}

func (c *dnsCache) isNegativeCacheEnabled() bool {
	cfg := c.config.Load()
	return cfg.Enabled && cfg.NegativeTTLEnabled
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
		// Unlink every element explicitly instead of calling lruList.Init().
		// Init() only resets the list root, leaving each Element's `list`
		// back-pointer aimed at this shard's live list. A concurrent hit that
		// captured the element before this lock then promotes it and
		// list.MoveToFront happily splices the orphan back in, desynchronising
		// the LRU from the map. list.Remove() clears e.list, which makes such a
		// stale MoveToFront a no-op.
		for shard.lruList.Len() > 0 {
			shard.lruList.Remove(shard.lruList.Back())
		}
		for _, e := range shard.entries {
			if e != nil {
				e.elem = nil
			}
		}
		shard.entries = make(map[string]*cacheEntry, shard.maxEntries)
		shard.mu.Unlock()
	}
}

func (c *dnsCache) shard(key string) *cacheShard {
	return c.shards[fnv32(key)%numDNSCacheShards]
}

func (c *dnsCache) shardOf(key []byte) *cacheShard {
	return c.shards[fnv32Bytes(key)%numDNSCacheShards]
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
	entry, resp, stale := c.lookup(rawQuery, true)
	if entry == nil {
		return nil, false, nil, nil, "", false, nil
	}
	if stale {
		return nil, false, entry.chainTargets, entry.ipList, entry.resolvedIPs, entry.isNegative, entry
	}
	return resp, true, entry.chainTargets, entry.ipList, entry.resolvedIPs, entry.isNegative, nil
}

// get maintains backwards compatibility with standard signature.
func (c *dnsCache) get(rawQuery []byte) (response []byte, hit bool, staleCandidate *cacheEntry) {
	resp, hit, _, _, _, _, stale := c.getFast(rawQuery)
	return resp, hit, stale
}

// lookup finds the entry for rawQuery. A fresh hit returns the entry and its
// patched response; a stale-fallback candidate returns the entry with stale
// set. When count is false the lookup is an internal re-check (single-flight)
// and leaves the hit/miss counters alone, so each client query is counted once.
func (c *dnsCache) lookup(rawQuery []byte, count bool) (entry *cacheEntry, response []byte, stale bool) {
	cfg := c.config.Load()
	if !cfg.Enabled || len(rawQuery) < 12 {
		return nil, nil, false
	}
	var buf [maxCacheKeyLen]byte
	key, _, ok := appendQuestionKey(buf[:0], rawQuery)
	if !ok {
		return nil, nil, false
	}
	queryID := binary.BigEndian.Uint16(rawQuery[0:2])
	now := time.Now()
	shard := c.shardOf(key)

	shard.mu.RLock()
	// string(key) in a map index does not allocate.
	entry = shard.entries[string(key)]
	if entry == nil {
		shard.mu.RUnlock()
		if count {
			c.totalMisses.Add(1)
		}
		return nil, nil, false
	}

	if now.Before(entry.expiresAt) {
		remainingSec := uint32(entry.expiresAt.Sub(now) / time.Second)
		if remainingSec == 0 {
			remainingSec = 1
		}
		response = patchWireResponse(entry.wire, entry.ttlOffsets, queryID, remainingSec)
		elem := entry.elem
		shard.mu.RUnlock()

		nowNano := now.UnixNano()
		lastHit := entry.lastHitAt.Swap(nowNano)
		if count {
			entry.hitCount.Add(1)
			c.totalHits.Add(1)
			if entry.isNegative {
				c.negativeHits.Add(1)
			}
		}
		// Promote at most once per lruPromoteInterval: a hot entry hit many
		// times a second would otherwise take the shard write lock on every
		// query and serialize readers.
		if elem != nil && nowNano-lastHit >= int64(lruPromoteInterval) {
			shard.mu.Lock()
			if elem.Value != nil && shard.lruList.Front() != elem {
				shard.lruList.MoveToFront(elem)
			}
			shard.mu.Unlock()
		}
		return entry, response, false
	}

	if cfg.StaleFallbackEnabled && now.Before(entry.staleUntil) {
		shard.mu.RUnlock()
		return entry, nil, true
	}
	shard.mu.RUnlock()

	// Completely expired: lazy eviction.
	shard.mu.Lock()
	if e := shard.entries[string(key)]; e == entry {
		c.removeLocked(shard, e)
	}
	shard.mu.Unlock()
	if count {
		c.totalMisses.Add(1)
	}
	return nil, nil, false
}

// removeLocked drops e from its shard; the caller holds shard.mu.
func (c *dnsCache) removeLocked(shard *cacheShard, e *cacheEntry) {
	delete(shard.entries, e.key)
	if e.elem != nil {
		shard.lruList.Remove(e.elem)
		e.elem = nil
	}
}

func (c *dnsCache) buildStaleResponse(rawQuery []byte, entry *cacheEntry) []byte {
	if entry == nil || len(entry.wire) < 12 || len(rawQuery) < 12 {
		return nil
	}
	c.staleHits.Add(1)
	return patchWireResponse(entry.wire, entry.ttlOffsets, binary.BigEndian.Uint16(rawQuery[0:2]), 1)
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
	// A truncated answer carries no complete records; caching it would replay
	// the TC=1 header to later clients even after the upstream recovered.
	if respMsg.Truncated {
		return false
	}
	cfg := c.getConfig()
	if !cfg.Enabled {
		return false
	}

	keyBytes, nameLen, ok := appendQuestionKey(make([]byte, 0, 64), rawQuery)
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

	key := string(keyBytes)
	domain, qtype, qclass := parseKeyQuestion(key, nameLen)
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
		c.removeLocked(shard, old)
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
