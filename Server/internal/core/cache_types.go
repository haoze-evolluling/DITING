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

	// 热点域名主动预取：在条目临近过期时后台回源刷新，避免热点到期后的首请求延迟
	PrefetchEnabled        bool  `json:"prefetchEnabled"`
	PrefetchThreshold      int   `json:"prefetchThreshold"`      // 命中次数门槛，默认 5
	PrefetchBeforeExpiryMs int64 `json:"prefetchBeforeExpiryMs"` // 剩余有效期阈值（毫秒），默认 30000

	// ExcludePatterns 为不参与缓存的域名正则；RE2 无回溯，天然免疫 ReDoS。
	// 默认空（全部缓存），未配置时热路径零额外开销。
	ExcludePatterns []string `json:"excludePatterns,omitempty"`

	// PersistEnabled 控制缓存是否落盘，默认关闭。
	//
	// 关闭是刻意的默认值：读取上次的应答会让"上游已变更但仍命中旧记录"
	// 这类问题变得难以察觉，用户应当明确选择开启。
	PersistEnabled bool `json:"persistEnabled"`
	// PersistPath 为落盘文件路径；空表示由调用方按平台约定推导
	PersistPath string `json:"persistPath,omitempty"`
	// PersistIntervalSeconds 为定时落盘间隔（秒），默认 300，钳制到 [30, 86400]。
	//
	// 0 与缺省不可区分（JSON 中同为缺省值），因此统一按默认值处理；
	// 想要"只在退出时落盘"请把间隔调到上限 86400。
	PersistIntervalSeconds int64 `json:"persistIntervalSeconds,omitempty"`
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

		PrefetchEnabled:        false,
		PrefetchThreshold:      defaultPrefetchThreshold,
		PrefetchBeforeExpiryMs: defaultPrefetchBeforeMs,
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
	PrefetchCount uint64  `json:"prefetchCount"`
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
	// group 记录条目所属客户端分组，供按组剔除与预取回源使用。
	// key 里虽含组后缀，但反解字符串既脆弱又依赖分隔符约定。
	group        string
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

	// lastPrefetchAt 最近一次主动预取回源时间（Unix 纳秒），用于抑制高频重复刷新
	lastPrefetchAt atomic.Int64
}

// cacheShard 内部独立分片
type cacheShard struct {
	mu         sync.RWMutex
	entries    map[string]*cacheEntry
	lruList    *list.List
	maxEntries int
}
