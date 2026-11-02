// dns_cache_policy.go implements cache policy normalization, key generation,
// TTL evaluation according to RFC 2181 / RFC 2308, and active background eviction.

package tunnel

import (
	"strconv"
	"strings"
	"time"
)

func normalizeDNSCacheConfig(cfg *dnsCacheConfig) {
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
	if cfg.NegativeTTLSeconds <= 0 {
		cfg.NegativeTTLSeconds = 30
	}
	if !cfg.NegativeTTLEnabled && cfg.Enabled {
		cfg.NegativeTTLEnabled = true
	}
}

func cacheKey(domain string, qtype, qclass uint16) string {
	normalized := strings.ToLower(strings.TrimSuffix(domain, "."))
	// Same "name:qtype:qclass" format as before, without fmt's reflection and boxing.
	buf := make([]byte, 0, len(normalized)+12)
	buf = append(buf, normalized...)
	buf = append(buf, ':')
	buf = strconv.AppendUint(buf, uint64(qtype), 10)
	buf = append(buf, ':')
	buf = strconv.AppendUint(buf, uint64(qclass), 10)
	return string(buf)
}

func fnv32(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

func fnv32Bytes(b []byte) uint32 {
	h := uint32(2166136261)
	for _, x := range b {
		h ^= uint32(x)
		h *= 16777619
	}
	return h
}

func (c *dnsCache) calculateEffectiveTTL(upstreamTTL uint32, cfg dnsCacheConfig) time.Duration {
	ttl := int64(upstreamTTL)
	switch strings.ToLower(cfg.Mode) {
	case "follow_dns_ttl":

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

func (c *dnsCache) calculateNegativeTTL(soaTTL uint32, found bool, cfg dnsCacheConfig) time.Duration {
	negTTL := int64(soaTTL)
	if !found || negTTL <= 0 || (cfg.NegativeTTLSeconds > 0 && negTTL > cfg.NegativeTTLSeconds) {
		negTTL = cfg.NegativeTTLSeconds
	}
	if negTTL <= 0 {
		negTTL = 30
	}
	if negTTL < 5 {
		negTTL = 5
	}
	if negTTL > 300 {
		negTTL = 300
	}
	return time.Duration(negTTL) * time.Second
}

// cleanerInterval paces the background sweep. Lookups already evict expired
// entries lazily and the LRU bounds memory, so the sweep only reclaims entries
// nobody asks for again and can run rarely.
const cleanerInterval = 60 * time.Second

func (c *dnsCache) startCleaner() {
	ticker := time.NewTicker(cleanerInterval)
	go func() {
		for {
			select {
			case <-c.stopCleaner:
				ticker.Stop()
				return
			case now := <-ticker.C:
				c.cleanupExpired(now)
			}
		}
	}()
}

func (c *dnsCache) cleanupExpired(now time.Time) {
	for _, shard := range c.shards {
		// Scan under the read lock first so idle shards never block lookups.
		shard.mu.RLock()
		expired := false
		for _, entry := range shard.entries {
			if entry != nil && now.After(entry.staleUntil) {
				expired = true
				break
			}
		}
		shard.mu.RUnlock()
		if !expired {
			continue
		}
		shard.mu.Lock()
		for _, entry := range shard.entries {
			if entry != nil && now.After(entry.staleUntil) {
				c.removeLocked(shard, entry)
				c.evictions.Add(1)
			}
		}
		shard.mu.Unlock()
	}
}
