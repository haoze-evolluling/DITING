package core

import (
	"sort"
	"strings"
	"time"

	"github.com/miekg/dns"
)

// Stats 生成缓存当前运行与命中指标快照
func (c *DNSCache) Stats() CacheStats {
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

	return CacheStats{
		Enabled:       c.IsEnabled(),
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

// GetEntries 跨分片检索缓存条目，支持关键字过滤与条数限制
func (c *DNSCache) GetEntries(query string, limit int) (int, []CacheEntryItem) {
	if limit <= 0 {
		limit = 100
	}
	query = strings.ToLower(strings.TrimSpace(query))
	now := time.Now()

	var allMatched []*cacheEntry
	for _, shard := range c.shards {
		shard.mu.RLock()
		for _, e := range shard.entries {
			if e == nil {
				continue
			}
			qtypeStr := dns.TypeToString[e.qtype]
			if query == "" || strings.Contains(e.domain, query) || strings.Contains(strings.ToLower(qtypeStr), query) {
				allMatched = append(allMatched, e)
			}
		}
		shard.mu.RUnlock()
	}

	// 按最近访问时间降序排列
	sort.Slice(allMatched, func(i, j int) bool {
		return allMatched[i].lastHitAt.Load() > allMatched[j].lastHitAt.Load()
	})

	total := len(allMatched)
	take := total
	if take > limit {
		take = limit
	}

	items := make([]CacheEntryItem, 0, take)
	for i := 0; i < take; i++ {
		e := allMatched[i]
		remainingTTL := int64(e.expiresAt.Sub(now).Seconds())
		status := "fresh"
		if remainingTTL <= 0 {
			remainingTTL = 0
			status = "stale"
		}

		items = append(items, CacheEntryItem{
			Domain:       e.domain,
			QType:        dns.TypeToString[e.qtype],
			TTL:          uint32(e.effectiveTTL.Seconds()),
			OriginalTTL:  e.originalTTL,
			RemainingTTL: remainingTTL,
			ExpiresAt:    e.expiresAt.UnixMilli(),
			StaleUntil:   e.staleUntil.UnixMilli(),
			HitCount:     e.hitCount.Load(),
			LastHitAt:    e.lastHitAt.Load() / 1e6,
			IsNegative:   e.isNegative,
			Status:       status,
			IPList:       e.ipList,
		})
	}

	return total, items
}

// GetTopDomains 获取访问频次最高的热点域名排行榜
func (c *DNSCache) GetTopDomains(limit int) []CacheDomainStat {
	if limit <= 0 {
		limit = 10
	}

	var allEntries []*cacheEntry
	for _, shard := range c.shards {
		shard.mu.RLock()
		for _, e := range shard.entries {
			if e != nil {
				allEntries = append(allEntries, e)
			}
		}
		shard.mu.RUnlock()
	}

	sort.Slice(allEntries, func(i, j int) bool {
		return allEntries[i].hitCount.Load() > allEntries[j].hitCount.Load()
	})

	if len(allEntries) > limit {
		allEntries = allEntries[:limit]
	}

	stats := make([]CacheDomainStat, 0, len(allEntries))
	for _, e := range allEntries {
		stats = append(stats, CacheDomainStat{
			Domain:    e.domain,
			QType:     dns.TypeToString[e.qtype],
			HitCount:  e.hitCount.Load(),
			LastHitAt: e.lastHitAt.Load() / 1e6,
		})
	}
	return stats
}
