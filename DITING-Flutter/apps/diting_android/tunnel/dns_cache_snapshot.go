// dns_cache_snapshot.go exposes the in-memory LRU as a JSON snapshot so the Android
// layer can mirror it into the `dns_cache` table that the Flutter UI reads.
//
// The cache itself stays authoritative: this is a read-only projection rebuilt on
// every call, ordered by hit count so the caller can cap the mirrored rows.

package tunnel

import (
	"encoding/json"
	"sort"
	"time"
)

// dnsCacheEntrySnapshot mirrors one live cache entry; field names match the
// `dns_cache` columns the Dart repositories read.
type dnsCacheEntrySnapshot struct {
	Key          string `json:"key"`
	QueryName    string `json:"queryName"`
	QueryType    int    `json:"queryType"`
	QueryClass   int    `json:"queryClass"`
	CreatedAt    int64  `json:"createdAt"`
	ExpiresAt    int64  `json:"expiresAt"`
	LastHitAt    int64  `json:"lastHitAt"`
	HitCount     uint64 `json:"hitCount"`
	OriginalTTL  int64  `json:"originalTtlSeconds"`
	ResponseSize int    `json:"responseSize"`
}

// snapshot returns up to limit unexpired entries, hottest first. Entries past
// their expiry are skipped: the engine cannot serve them any more, and the
// repository queries filter them out anyway.
func (c *dnsCache) snapshot(now time.Time, limit int) []dnsCacheEntrySnapshot {
	if c == nil || limit <= 0 {
		return nil
	}
	out := make([]dnsCacheEntrySnapshot, 0, limit)
	for _, shard := range c.shards {
		shard.mu.RLock()
		for _, entry := range shard.entries {
			if entry == nil || !now.Before(entry.expiresAt) {
				continue
			}
			out = append(out, dnsCacheEntrySnapshot{
				Key:          entry.key,
				QueryName:    entry.domain,
				QueryType:    int(entry.qtype),
				QueryClass:   int(entry.qclass),
				CreatedAt:    entry.createdAt.UnixMilli(),
				ExpiresAt:    entry.expiresAt.UnixMilli(),
				LastHitAt:    entry.lastHitAt.Load() / int64(time.Millisecond),
				HitCount:     entry.hitCount.Load(),
				OriginalTTL:  int64(entry.originalTTL),
				ResponseSize: len(entry.wire),
			})
		}
		shard.mu.RUnlock()
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].HitCount != out[j].HitCount {
			return out[i].HitCount > out[j].HitCount
		}
		return out[i].ExpiresAt > out[j].ExpiresAt
	})
	if len(out) > limit {
		out = out[:limit]
	}
	return out
}

func (c *dnsCache) snapshotJSON(limit int) string {
	entries := c.snapshot(time.Now(), limit)
	b, err := json.Marshal(entries)
	if err != nil {
		return "[]"
	}
	return string(b)
}
