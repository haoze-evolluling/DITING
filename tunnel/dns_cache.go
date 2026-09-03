package tunnel

import (
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

// dnsCacheConfig defines the runtime configuration for DNS caching.
type dnsCacheConfig struct {
	Enabled              bool   `json:"enabled"`
	Mode                 string `json:"mode"`
	MaxTTLSeconds        int64  `json:"maxTtlSeconds"`
	FixedTTLSeconds      int64  `json:"fixedTtlSeconds"`
	MinTTLEnabled        bool   `json:"minTtlEnabled"`
	MinTTLSeconds        int64  `json:"minTtlSeconds"`
	StaleFallbackEnabled bool   `json:"staleFallbackEnabled"`
	StaleFallbackSeconds int64  `json:"staleFallbackSeconds"`
}

type cacheEntry struct {
	key          string
	domain       string
	qtype        uint16
	qclass       uint16
	msg          *dns.Msg
	originalTTL  uint32
	effectiveTTL time.Duration
	createdAt    time.Time
	expiresAt    time.Time
	staleUntil   time.Time
	hitCount     int64
	lastHitAt    time.Time
}

// dnsCache provides a thread-safe in-memory cache for DNS responses.
type dnsCache struct {
	mu         sync.RWMutex
	config     dnsCacheConfig
	entries    map[string]*cacheEntry
	maxEntries int

	flightMu sync.Mutex
	inFlight map[string]*flightCall

	totalHits   atomic.Uint64
	totalMisses atomic.Uint64
}

type flightCall struct {
	wg  sync.WaitGroup
	val []byte
	err error
}

const defaultMaxCacheEntries = 4096

// newDNSCache creates a new dnsCache instance.
func newDNSCache(cfg dnsCacheConfig) *dnsCache {
	if cfg.MaxTTLSeconds <= 0 {
		cfg.MaxTTLSeconds = 3600
	}
	if cfg.FixedTTLSeconds <= 0 {
		cfg.FixedTTLSeconds = 3600
	}
	if cfg.MinTTLSeconds <= 0 {
		cfg.MinTTLSeconds = 60
	}
	if cfg.StaleFallbackSeconds <= 0 {
		cfg.StaleFallbackSeconds = 300
	}
	return &dnsCache{
		config:     cfg,
		entries:    make(map[string]*cacheEntry),
		maxEntries: defaultMaxCacheEntries,
		inFlight:   make(map[string]*flightCall),
	}
}

// updatePolicy updates the cache policy dynamically.
func (c *dnsCache) updatePolicy(cfg dnsCacheConfig) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.config = cfg
}

// isEnabled returns true if caching is enabled.
func (c *dnsCache) isEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.config.Enabled
}

// clear removes all entries from the cache.
func (c *dnsCache) clear() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries = make(map[string]*cacheEntry)
}

// cacheKey returns the lookup key for a DNS question.
func cacheKey(domain string, qtype, qclass uint16) string {
	normalized := strings.ToLower(strings.TrimSuffix(domain, "."))
	return fmt.Sprintf("%s:%d:%d", normalized, qtype, qclass)
}

func extractQuestionFromRaw(rawQuery []byte) (string, uint16, uint16, uint16, bool) {
	var msg dns.Msg
	if err := msg.Unpack(rawQuery); err != nil || len(msg.Question) == 0 {
		return "", 0, 0, 0, false
	}
	q := msg.Question[0]
	domain := strings.ToLower(strings.TrimSuffix(q.Name, "."))
	return domain, q.Qtype, q.Qclass, msg.Id, true
}

// get checks the cache for a matching unexpired response.
// If an unexpired entry is found, it returns the patched response bytes with hit=true.
// If an expired entry within the stale fallback window is found, it returns staleCandidate with stale=true.
func (c *dnsCache) get(rawQuery []byte) (response []byte, hit bool, staleCandidate *cacheEntry) {
	c.mu.RLock()
	enabled := c.config.Enabled
	staleFallback := c.config.StaleFallbackEnabled
	c.mu.RUnlock()

	if !enabled {
		return nil, false, nil
	}

	domain, qtype, qclass, queryID, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		return nil, false, nil
	}

	key := cacheKey(domain, qtype, qclass)
	now := time.Now()

	c.mu.RLock()
	entry, exists := c.entries[key]
	c.mu.RUnlock()

	if !exists || entry == nil {
		c.totalMisses.Add(1)
		return nil, false, nil
	}

	if now.Before(entry.expiresAt) {
		remaining := entry.expiresAt.Sub(now)
		remainingSec := uint32(remaining.Seconds())
		if remainingSec == 0 {
			remainingSec = 1
		}

		c.mu.Lock()
		entry.hitCount++
		entry.lastHitAt = now
		c.mu.Unlock()

		c.totalHits.Add(1)
		patched := patchDNSResponse(entry.msg, queryID, remainingSec)
		return patched, true, nil
	}

	if staleFallback && now.Before(entry.staleUntil) {
		return nil, false, entry
	}

	// Past stale window, trigger asynchronous eviction
	c.mu.Lock()
	if e, ok := c.entries[key]; ok && e == entry && now.After(e.staleUntil) {
		delete(c.entries, key)
	}
	c.mu.Unlock()

	c.totalMisses.Add(1)
	return nil, false, nil
}

// buildStaleResponse generates a response from a stale cache entry with TTL=1s.
func (c *dnsCache) buildStaleResponse(rawQuery []byte, entry *cacheEntry) []byte {
	if entry == nil || entry.msg == nil {
		return nil
	}
	_, _, _, queryID, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		return nil
	}
	return patchDNSResponse(entry.msg, queryID, 1)
}

// put stores a successful upstream DNS response into the cache.
func (c *dnsCache) put(rawQuery, rawResponse []byte) bool {
	c.mu.RLock()
	enabled := c.config.Enabled
	c.mu.RUnlock()
	if !enabled {
		return false
	}

	domain, qtype, qclass, _, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		return false
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(rawResponse); err != nil {
		return false
	}

	// Only cache NOERROR responses with answers
	if respMsg.Rcode != dns.RcodeSuccess || len(respMsg.Answer) == 0 {
		return false
	}

	minTTL, found := extractMinTTL(&respMsg)
	if !found || minTTL == 0 {
		return false
	}

	effectiveTTL := c.calculateEffectiveTTL(minTTL)
	if effectiveTTL <= 0 {
		return false
	}

	now := time.Now()
	expiresAt := now.Add(effectiveTTL)

	c.mu.RLock()
	staleFallback := c.config.StaleFallbackEnabled
	staleSeconds := c.config.StaleFallbackSeconds
	c.mu.RUnlock()

	staleUntil := expiresAt
	if staleFallback && staleSeconds > 0 {
		staleUntil = expiresAt.Add(time.Duration(staleSeconds) * time.Second)
	}

	entry := &cacheEntry{
		key:          cacheKey(domain, qtype, qclass),
		domain:       domain,
		qtype:        qtype,
		qclass:       qclass,
		msg:          respMsg.Copy(),
		originalTTL:  minTTL,
		effectiveTTL: effectiveTTL,
		createdAt:    now,
		expiresAt:    expiresAt,
		staleUntil:   staleUntil,
		hitCount:     0,
		lastHitAt:    now,
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	if len(c.entries) >= c.maxEntries {
		c.evictOldestLocked(now)
	}

	c.entries[entry.key] = entry
	return true
}

func (c *dnsCache) calculateEffectiveTTL(upstreamTTL uint32) time.Duration {
	c.mu.RLock()
	cfg := c.config
	c.mu.RUnlock()

	ttl := int64(upstreamTTL)
	switch strings.ToLower(cfg.Mode) {
	case "follow_dns_ttl":
		// Follow upstream TTL directly
	case "limit_max_ttl":
		if cfg.MaxTTLSeconds > 0 && ttl > cfg.MaxTTLSeconds {
			ttl = cfg.MaxTTLSeconds
		}
	case "fixed_ttl":
		if cfg.FixedTTLSeconds > 0 {
			ttl = cfg.FixedTTLSeconds
		}
	default:
		if cfg.MaxTTLSeconds > 0 && ttl > cfg.MaxTTLSeconds {
			ttl = cfg.MaxTTLSeconds
		}
	}

	if cfg.MinTTLEnabled && cfg.MinTTLSeconds > 0 {
		if ttl < cfg.MinTTLSeconds {
			ttl = cfg.MinTTLSeconds
		}
	}

	if ttl <= 0 {
		return 0
	}
	return time.Duration(ttl) * time.Second
}

func (c *dnsCache) evictOldestLocked(now time.Time) {
	// First pass: remove expired entries
	for k, e := range c.entries {
		if now.After(e.staleUntil) {
			delete(c.entries, k)
			if len(c.entries) < c.maxEntries {
				return
			}
		}
	}

	// Second pass: remove oldest created entries (FIFO / LRU approximation)
	var oldestKey string
	var oldestTime time.Time
	for k, e := range c.entries {
		if oldestKey == "" || e.createdAt.Before(oldestTime) {
			oldestKey = k
			oldestTime = e.createdAt
		}
	}
	if oldestKey != "" {
		delete(c.entries, oldestKey)
	}
}

// singleFlight resolves a query with deduplication so multiple concurrent identical queries
// only trigger one upstream resolution.
func (c *dnsCache) singleFlight(rawQuery []byte, resolveFn func() ([]byte, error)) ([]byte, bool, error) {
	domain, qtype, qclass, queryID, ok := extractQuestionFromRaw(rawQuery)
	if !ok {
		resp, err := resolveFn()
		return resp, false, err
	}

	// Fast path: check unexpired cache response before upstream resolution
	if cachedResp, hit, _ := c.get(rawQuery); hit {
		return cachedResp, true, nil
	}

	key := cacheKey(domain, qtype, qclass)

	c.flightMu.Lock()
	if call, exists := c.inFlight[key]; exists {
		c.flightMu.Unlock()
		call.wg.Wait()
		if call.err != nil {
			return nil, false, call.err
		}
		// Try reading from cache after flight completes
		if cachedResp, hit, _ := c.get(rawQuery); hit {
			return cachedResp, true, nil
		}
		// If not in cache, patch ID on returned flight value
		var msg dns.Msg
		if err := msg.Unpack(call.val); err == nil {
			msg.Id = queryID
			packed, err := msg.Pack()
			if err == nil {
				return packed, true, nil
			}
		}
		return call.val, true, nil
	}

	call := &flightCall{}
	call.wg.Add(1)
	c.inFlight[key] = call
	c.flightMu.Unlock()

	call.val, call.err = resolveFn()
	if call.err == nil && len(call.val) > 0 {
		c.put(rawQuery, call.val)
	}
	call.wg.Done()

	c.flightMu.Lock()
	delete(c.inFlight, key)
	c.flightMu.Unlock()

	return call.val, false, call.err
}

func extractMinTTL(msg *dns.Msg) (uint32, bool) {
	var minTTL uint32
	found := false

	scanRRs := func(rrs []dns.RR) {
		for _, rr := range rrs {
			if rr == nil || rr.Header() == nil || rr.Header().Rrtype == dns.TypeOPT {
				continue
			}
			ttl := rr.Header().Ttl
			if !found || ttl < minTTL {
				minTTL = ttl
				found = true
			}
		}
	}

	scanRRs(msg.Answer)
	scanRRs(msg.Ns)
	scanRRs(msg.Extra)

	return minTTL, found
}

func patchDNSResponse(msg *dns.Msg, queryID uint16, ttl uint32) []byte {
	if msg == nil {
		return nil
	}
	cp := msg.Copy()
	cp.Id = queryID

	patchRRs := func(rrs []dns.RR) {
		for _, rr := range rrs {
			if rr == nil || rr.Header() == nil || rr.Header().Rrtype == dns.TypeOPT {
				continue
			}
			rr.Header().Ttl = ttl
		}
	}

	patchRRs(cp.Answer)
	patchRRs(cp.Ns)
	patchRRs(cp.Extra)

	packed, err := cp.Pack()
	if err != nil {
		return nil
	}
	return packed
}
