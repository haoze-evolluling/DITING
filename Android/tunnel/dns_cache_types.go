// dns_cache_types.go defines the core data structures, configuration options,
// and telemetry models for the sharded in-memory DNS cache.

package tunnel

import (
	"container/list"
	"sync"
	"sync/atomic"
	"time"
)

const (
	numDNSCacheShards      = 64
	defaultMaxCacheEntries = 4096
)

type dnsCacheConfig struct {
	Enabled              bool   `json:"enabled"`
	Mode                 string `json:"mode"`
	MaxTTLSeconds        int64  `json:"maxTtlSeconds"`
	FixedTTLSeconds      int64  `json:"fixedTtlSeconds"`
	MinTTLEnabled        bool   `json:"minTtlEnabled"`
	MinTTLSeconds        int64  `json:"minTtlSeconds"`
	StaleFallbackEnabled bool   `json:"staleFallbackEnabled"`
	StaleFallbackSeconds int64  `json:"staleFallbackSeconds"`
	NegativeTTLEnabled   bool   `json:"negativeTtlEnabled"`
	NegativeTTLSeconds   int64  `json:"negativeTtlSeconds"`
}

type chainTarget struct {
	domain string
	kind   string
}

type cacheEntry struct {
	key          string
	domain       string
	qtype        uint16
	qclass       uint16
	wire         []byte
	ttlOffsets   []uint16
	originalTTL  uint32
	effectiveTTL time.Duration
	createdAt    time.Time
	expiresAt    time.Time
	staleUntil   time.Time
	isNegative   bool
	rcode        int
	chainTargets []chainTarget
	ipList       []string
	resolvedIPs  string

	hitCount  atomic.Uint64
	lastHitAt atomic.Int64
	elem      *list.Element
}

type cacheShard struct {
	mu         sync.RWMutex
	entries    map[string]*cacheEntry
	lruList    *list.List
	maxEntries int
}

type dnsCacheStats struct {
	Enabled       bool    `json:"enabled"`
	TotalHits     uint64  `json:"totalHits"`
	TotalMisses   uint64  `json:"totalMisses"`
	StaleHits     uint64  `json:"staleHits"`
	NegativeHits  uint64  `json:"negativeHits"`
	HitRatio      float64 `json:"hitRatio"`
	EntryCount    int     `json:"entryCount"`
	MaxEntries    int     `json:"maxEntries"`
	EvictionCount uint64  `json:"evictionCount"`
}
