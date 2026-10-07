package core

import (
	"container/list"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

const (
	// NumDNSCacheShards 分片数量 (64 分片并发安全)
	NumDNSCacheShards = 64
	// DefaultMaxCacheEntries 默认最大缓存条目容量
	DefaultMaxCacheEntries = 4096
)

// CacheConfig 智能缓存运行与策略配置
type CacheConfig struct {
	Enabled              bool   `json:"enabled"`
	MaxEntries           int    `json:"maxEntries"`
	Mode                 string `json:"mode"` // "follow_dns_ttl" | "limit_max_ttl" | "fixed_ttl"
	MaxTTLSeconds        int64  `json:"maxTtlSeconds"`
	FixedTTLSeconds      int64  `json:"fixedTtlSeconds"`
	MinTTLEnabled        bool   `json:"minTtlEnabled"`
	MinTTLSeconds        int64  `json:"minTtlSeconds"`
	StaleFallbackEnabled bool   `json:"staleFallbackEnabled"`
	StaleFallbackSeconds int64  `json:"staleFallbackSeconds"`
	NegativeTTLEnabled   bool   `json:"negativeTtlEnabled"`
	NegativeTTLSeconds   int64  `json:"negativeTtlSeconds"`
	Optimistic           bool   `json:"optimistic"` // Optimistic Stale-While-Revalidate (SWR)
}

// DefaultCacheConfig 返回标准默认缓存配置
func DefaultCacheConfig() CacheConfig {
	return CacheConfig{
		Enabled:              true,
		MaxEntries:           DefaultMaxCacheEntries,
		Mode:                 "limit_max_ttl",
		MaxTTLSeconds:        3600,
		FixedTTLSeconds:      3600,
		MinTTLEnabled:        true,
		MinTTLSeconds:        60,
		StaleFallbackEnabled: true,
		StaleFallbackSeconds: 300,
		NegativeTTLEnabled:   true,
		NegativeTTLSeconds:   30,
		Optimistic:           true,
	}
}

// CacheStats 缓存运行时指标统计
type CacheStats struct {
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

// CacheEntryItem 供 IPC 传输与 UI 呈现的单个缓存条目详情
type CacheEntryItem struct {
	Domain       string   `json:"domain"`
	QType        string   `json:"qtype"`
	TTL          uint32   `json:"ttl"`
	OriginalTTL  uint32   `json:"originalTtl"`
	RemainingTTL int64    `json:"remainingTtl"`
	ExpiresAt    int64    `json:"expiresAt"`
	StaleUntil   int64    `json:"staleUntil"`
	HitCount     uint64   `json:"hitCount"`
	LastHitAt    int64    `json:"lastHitAt"`
	IsNegative   bool     `json:"isNegative"`
	Status       string   `json:"status"` // "fresh" | "stale"
	IPList       []string `json:"ipList,omitempty"`
}

// CacheDomainStat 热点域名排行统计
type CacheDomainStat struct {
	Domain    string `json:"domain"`
	QType     string `json:"qtype"`
	HitCount  uint64 `json:"hitCount"`
	LastHitAt int64  `json:"lastHitAt"`
}

// cacheEntry 内部缓存条目模型
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
	isNegative   bool
	rcode        int
	ipList       []string

	hitCount  atomic.Uint64
	lastHitAt atomic.Int64
	elem      *list.Element
}

// cacheShard 内部独立分片
type cacheShard struct {
	mu         sync.RWMutex
	entries    map[string]*cacheEntry
	lruList    *list.List
	maxEntries int
}
