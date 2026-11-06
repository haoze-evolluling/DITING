// dns_cache_snapshot.go exposes the live cache entries as a JSON snapshot so the Android layer can
// mirror them into the `dns_cache` table that the Flutter UI reads.
//
// The Rust container stays authoritative: this is a read-only projection rebuilt on every call,
// ordered by hit count so the caller can cap the mirrored rows.

package tunnel

import "encoding/json"

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

// snapshot returns up to limit unexpired entries, hottest first. The kernel skips entries past
// their expiry: the engine cannot serve them any more, and the repository queries filter them out
// anyway.
func (c *dnsCache) snapshot(limit int) []dnsCacheEntrySnapshot {
	if c == nil || c.handle == nil || limit <= 0 {
		return nil
	}
	entries, err := c.handle.snapshot(uint32(limit))
	if err != nil {
		logf("dnsCache: snapshot failed: %v", err)
		return nil
	}
	return entries
}

func (c *dnsCache) snapshotJSON(limit int) string {
	entries := c.snapshot(limit)
	if entries == nil {
		return "[]"
	}
	b, err := json.Marshal(entries)
	if err != nil {
		return "[]"
	}
	return string(b)
}
