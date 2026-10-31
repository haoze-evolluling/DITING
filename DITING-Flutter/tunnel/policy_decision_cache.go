// policy_decision_cache.go keeps a bounded cache of recent policy decisions per rule snapshot,
// plus hot-domain prewarming across snapshot swaps.
//
// Cache key: the normalized domain, plus the app name only when the snapshot has app-dependent
// rules, and the qtype only when some rule has a dnsType constraint. When neither applies, every
// app and query type shares one entry per domain.
//
// Eviction: each shard is a fixed ring swept by a CLOCK hand with frequency aging, so lookups
// only take a read lock and bump atomics. Hit counts drive both eviction and prewarm ranking.
//
// Prewarming: when a new snapshot is published, the most-hit keys of the previous cache are
// re-evaluated against the new snapshot in a background goroutine. High-frequency domains stay
// fast right after a rule reload instead of all missing at once.
//
// A cache belongs to exactly one immutable snapshot, so rule changes never serve stale results.

package tunnel

import (
	"hash/maphash"
	"sort"
	"sync"
	"sync/atomic"
)

const (
	decisionCacheShards      = 16
	decisionCacheShardSize   = 512 // 8192 entries in total
	decisionCachePrewarmTopN = 512
)

type decisionKey struct {
	domain string
	app    string
	qtype  uint16
}

type decisionEntry struct {
	key     decisionKey
	blocked bool
	reason  string
	hits    atomic.Uint32
	ref     atomic.Bool
}

type decisionShard struct {
	mu      sync.RWMutex
	index   map[decisionKey]int32
	entries []*decisionEntry
	hand    int
}

type decisionCache struct {
	seed   maphash.Seed
	shards [decisionCacheShards]decisionShard
}

func newDecisionCache() *decisionCache {
	c := &decisionCache{seed: maphash.MakeSeed()}
	for i := range c.shards {
		c.shards[i].index = make(map[decisionKey]int32, decisionCacheShardSize)
		c.shards[i].entries = make([]*decisionEntry, 0, decisionCacheShardSize)
	}
	return c
}

func (c *decisionCache) shard(k decisionKey) *decisionShard {
	h := maphash.String(c.seed, k.domain)
	if k.app != "" {
		h ^= maphash.String(c.seed, k.app) * 0x9e3779b97f4a7c15
	}
	h ^= uint64(k.qtype)
	return &c.shards[h%decisionCacheShards]
}

func (c *decisionCache) get(k decisionKey) (blocked bool, reason string, ok bool) {
	s := c.shard(k)
	s.mu.RLock()
	i, found := s.index[k]
	var e *decisionEntry
	if found {
		e = s.entries[i]
	}
	s.mu.RUnlock()
	if e == nil {
		return false, "", false
	}
	e.ref.Store(true)
	e.hits.Add(1)
	return e.blocked, e.reason, true
}

func (c *decisionCache) put(k decisionKey, blocked bool, reason string, hits uint32) {
	s := c.shard(k)
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.index[k]; exists {
		return
	}
	e := &decisionEntry{key: k, blocked: blocked, reason: reason}
	e.hits.Store(hits)
	if len(s.entries) < decisionCacheShardSize {
		s.index[k] = int32(len(s.entries))
		s.entries = append(s.entries, e)
		return
	}
	// CLOCK with frequency aging: a recently used entry gets a second chance,
	// and a frequently used one has its hit count halved instead of being
	// evicted, so a burst of one-off domains cannot flush hot domains.
	for {
		victim := s.entries[s.hand]
		if victim.ref.Swap(false) {
			s.hand = (s.hand + 1) % len(s.entries)
			continue
		}
		if h := victim.hits.Load(); h >= 2 {
			victim.hits.Store(h / 2)
			s.hand = (s.hand + 1) % len(s.entries)
			continue
		}
		delete(s.index, victim.key)
		s.entries[s.hand] = e
		s.index[k] = int32(s.hand)
		s.hand = (s.hand + 1) % len(s.entries)
		return
	}
}

// hottest returns up to n keys with the highest hit counts.
func (c *decisionCache) hottest(n int) []decisionKey {
	type ranked struct {
		key  decisionKey
		hits uint32
	}
	var all []ranked
	for i := range c.shards {
		s := &c.shards[i]
		s.mu.RLock()
		for _, e := range s.entries {
			if h := e.hits.Load(); h > 0 {
				all = append(all, ranked{e.key, h})
			}
		}
		s.mu.RUnlock()
	}
	sort.Slice(all, func(i, j int) bool { return all[i].hits > all[j].hits })
	if len(all) > n {
		all = all[:n]
	}
	keys := make([]decisionKey, len(all))
	for i, r := range all {
		keys[i] = r.key
	}
	return keys
}

// cacheKey builds the decision key, dropping dimensions the snapshot never inspects.
func (s *policySnapshot) cacheKey(domain, appName string, qtype uint16) decisionKey {
	k := decisionKey{domain: domain}
	if s.appSensitive {
		k.app = appName
	}
	if s.qtypeSensitive {
		k.qtype = qtype
	}
	return k
}

// prewarmFrom re-evaluates the hottest keys of prev against s. Keys are only
// carried over when both snapshots agree on which dimensions matter.
func (s *policySnapshot) prewarmFrom(prev *policySnapshot) {
	if s == nil || prev == nil || s.cache == nil || prev.cache == nil {
		return
	}
	if !s.filterEnabled || !s.hasRules {
		return
	}
	if s.appSensitive != prev.appSensitive || s.qtypeSensitive != prev.qtypeSensitive {
		return
	}
	for _, k := range prev.cache.hottest(decisionCachePrewarmTopN) {
		blocked, reason := s.evaluateUncached(k.domain, k.app, k.qtype)
		// Carry no hits over, so one reload cannot pin old hot keys forever.
		s.cache.put(k, blocked, reason, 0)
	}
}

// finalizeLookup derives the cache dimensions from the parsed rules and
// attaches a fresh decision cache. Call it once, before publishing.
func (s *policySnapshot) finalizeLookup() {
	s.appSensitive = len(s.appBuckets) > 0
	for _, list := range [][]invertedRule{s.importantInverted, s.allowInverted, s.blockInverted} {
		for _, inv := range list {
			if len(inv.excludedApps) > 0 {
				s.appSensitive = true
			}
		}
	}
	for _, list := range [][]*specialRule{
		s.importantAppBlockSpecial, s.importantGlobalBlockSpecial, s.appAllowSpecial,
		s.globalAllowSpecial, s.appBlockSpecial, s.globalBlockSpecial,
	} {
		for _, r := range list {
			if len(r.appScope) > 0 {
				s.appSensitive = true
			}
			if len(r.includeQtypes) > 0 || len(r.excludeQtypes) > 0 {
				s.qtypeSensitive = true
			}
		}
	}
	if s.filterEnabled && s.hasRules {
		s.cache = newDecisionCache()
	}
}
