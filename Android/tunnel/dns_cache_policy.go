// dns_cache_policy.go implements cache policy normalization, key generation,
// TTL evaluation according to RFC 2181 / RFC 2308, and active background eviction.

package tunnel

import (
	"fmt"
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
	return fmt.Sprintf("%s:%d:%d", normalized, qtype, qclass)
}

func fnv32(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
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

func (c *dnsCache) startCleaner() {
	ticker := time.NewTicker(30 * time.Second)
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
		shard.mu.Lock()
		for key, entry := range shard.entries {
			if entry != nil && now.After(entry.staleUntil) {
				delete(shard.entries, key)
				if entry.elem != nil {
					shard.lruList.Remove(entry.elem)
					entry.elem = nil
				}
				c.evictions.Add(1)
			}
		}
		shard.mu.Unlock()
	}
}
