package core

import (
	"container/list"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

// DNSCache 实现 64 分片并发安全的高性能内存 LRU 缓存与 SWR 容灾体系
type DNSCache struct {
	configMu   sync.RWMutex
	config     CacheConfig
	shards     [NumDNSCacheShards]*cacheShard
	maxEntries int

	flight *singleFlightGroup

	totalHits    atomic.Uint64
	totalMisses  atomic.Uint64
	staleHits    atomic.Uint64
	negativeHits atomic.Uint64
	evictions    atomic.Uint64

	stopCleaner chan struct{}
	closed      atomic.Bool
}

// NewDNSCache 创建 64 分片智能缓存管理器
func NewDNSCache(cfg CacheConfig) *DNSCache {
	NormalizeCacheConfig(&cfg)

	maxEntries := cfg.MaxEntries
	if maxEntries <= 0 {
		maxEntries = DefaultMaxCacheEntries
	}
	entriesPerShard := maxEntries / NumDNSCacheShards
	if entriesPerShard <= 0 {
		entriesPerShard = 1
	}

	c := &DNSCache{
		config:      cfg,
		maxEntries:  maxEntries,
		flight:      newSingleFlightGroup(),
		stopCleaner: make(chan struct{}),
	}

	for i := 0; i < NumDNSCacheShards; i++ {
		c.shards[i] = &cacheShard{
			entries:    make(map[string]*cacheEntry, entriesPerShard),
			lruList:    list.New(),
			maxEntries: entriesPerShard,
		}
	}

	c.startCleaner()
	return c
}

// UpdateConfig 动态热更新缓存运行配置
func (c *DNSCache) UpdateConfig(cfg CacheConfig) {
	NormalizeCacheConfig(&cfg)
	c.configMu.Lock()
	c.config = cfg
	c.configMu.Unlock()
}

// GetConfig 获取当前配置副本
func (c *DNSCache) GetConfig() CacheConfig {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config
}

// IsEnabled 检查缓存是否处于启用状态
func (c *DNSCache) IsEnabled() bool {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled
}

// IsStaleFallbackEnabled 检查陈旧条目容灾保活是否开启
func (c *DNSCache) IsStaleFallbackEnabled() bool {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled && c.config.StaleFallbackEnabled
}

// IsOptimistic 检查是否开启 Optimistic Stale-While-Revalidate
func (c *DNSCache) IsOptimistic() bool {
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled && c.config.Optimistic
}

// Close 关闭缓存并终止后台主动过期协程
func (c *DNSCache) Close() {
	if c.closed.Swap(true) {
		return
	}
	close(c.stopCleaner)
}

// Clear 清空全部 64 分片的缓存条目并重置 LRU 链表
func (c *DNSCache) Clear() {
	for _, shard := range c.shards {
		shard.mu.Lock()
		for _, e := range shard.entries {
			if e != nil {
				e.elem = nil
			}
		}
		shard.entries = make(map[string]*cacheEntry, shard.maxEntries)
		shard.lruList.Init()
		shard.mu.Unlock()
	}
}

// shard 根据 key 的哈希值路由到对应的分片
func (c *DNSCache) shard(key string) *cacheShard {
	return c.shards[fnv32(key)%NumDNSCacheShards]
}

// Get 查询缓存条目并执行 LRU 提升与 TTL 剩余时长重写
func (c *DNSCache) Get(req *dns.Msg) (resp *dns.Msg, hit bool, isStale bool, staleCandidate *cacheEntry) {
	if !c.IsEnabled() || req == nil || len(req.Question) == 0 {
		return nil, false, false, nil
	}

	q := req.Question[0]
	key := CacheKey(q.Name, q.Qtype, q.Qclass)
	now := time.Now()
	shard := c.shard(key)

	shard.mu.RLock()
	entry, exists := shard.entries[key]
	if !exists || entry == nil {
		shard.mu.RUnlock()
		c.totalMisses.Add(1)
		return nil, false, false, nil
	}

	// 场景 1: 有效期内的新鲜缓存命中 (Fresh Hit)
	if now.Before(entry.expiresAt) {
		remainingSec := uint32(time.Until(entry.expiresAt).Seconds())
		if remainingSec == 0 {
			remainingSec = 1
		}

		entry.hitCount.Add(1)
		entry.lastHitAt.Store(now.UnixNano())
		c.totalHits.Add(1)
		if entry.isNegative {
			c.negativeHits.Add(1)
		}

		cloned := entry.msg.Copy()
		cloned.Id = req.Id
		RewriteTTL(cloned, remainingSec)
		elem := entry.elem
		shard.mu.RUnlock()

		// LRU 热度提升 (在写锁保护下安全检查与置顶)
		if elem != nil {
			shard.mu.Lock()
			if entry.elem == elem && elem.Value != nil && shard.lruList.Front() != elem {
				shard.lruList.MoveToFront(elem)
			}
			shard.mu.Unlock()
		}

		return cloned, true, false, nil
	}

	// 场景 2: 处于过期宽限期内的陈旧候选条目 (Stale Candidate)
	if c.IsStaleFallbackEnabled() && now.Before(entry.staleUntil) {
		shard.mu.RUnlock()
		return nil, false, true, entry
	}

	shard.mu.RUnlock()

	// 场景 3: 已彻底过期超过宽限期，惰性剔除
	shard.mu.Lock()
	if e, ok := shard.entries[key]; ok && e == entry && now.After(e.staleUntil) {
		delete(shard.entries, key)
		if e.elem != nil {
			shard.lruList.Remove(e.elem)
			e.elem = nil
		}
		c.evictions.Add(1)
	}
	shard.mu.Unlock()

	c.totalMisses.Add(1)
	return nil, false, false, nil
}

// BuildStaleResponse 为陈旧候选条目构造 TTL=1 的保活响应
func (c *DNSCache) BuildStaleResponse(req *dns.Msg, entry *cacheEntry) *dns.Msg {
	if entry == nil || entry.msg == nil || req == nil {
		return nil
	}
	cloned := entry.msg.Copy()
	cloned.Id = req.Id
	RewriteTTL(cloned, 1)
	entry.hitCount.Add(1)
	entry.lastHitAt.Store(time.Now().UnixNano())
	c.totalHits.Add(1)
	c.staleHits.Add(1)
	return cloned
}

// Put 解析上游响应并以 LRU 方式持久化至对应分片中
func (c *DNSCache) Put(req *dns.Msg, resp *dns.Msg) bool {
	if !c.IsEnabled() || req == nil || len(req.Question) == 0 || resp == nil {
		return false
	}

	cfg := c.GetConfig()
	if !cfg.Enabled {
		return false
	}

	q := req.Question[0]
	minTTL, found := ExtractMinTTL(resp)
	var effectiveTTL time.Duration
	isNegative := false

	if resp.Rcode == dns.RcodeNameError || (resp.Rcode == dns.RcodeSuccess && len(resp.Answer) == 0) {
		if !cfg.NegativeTTLEnabled {
			return false
		}
		isNegative = true
		effectiveTTL = CalculateNegativeTTL(minTTL, found, cfg)
	} else if resp.Rcode == dns.RcodeSuccess && len(resp.Answer) > 0 {
		effectiveTTL = CalculateEffectiveTTL(minTTL, cfg)
	} else {
		return false
	}

	if effectiveTTL <= 0 {
		return false
	}

	now := time.Now()
	expiresAt := now.Add(effectiveTTL)
	staleUntil := expiresAt
	if cfg.StaleFallbackEnabled && cfg.StaleFallbackSeconds > 0 {
		staleUntil = expiresAt.Add(time.Duration(cfg.StaleFallbackSeconds) * time.Second)
	}

	clonedMsg := resp.Copy()
	key := CacheKey(q.Name, q.Qtype, q.Qclass)
	entry := &cacheEntry{
		key:          key,
		domain:       strings.ToLower(strings.TrimSuffix(strings.TrimSpace(q.Name), ".")),
		qtype:        q.Qtype,
		qclass:       q.Qclass,
		msg:          clonedMsg,
		originalTTL:  minTTL,
		effectiveTTL: effectiveTTL,
		createdAt:    now,
		expiresAt:    expiresAt,
		staleUntil:   staleUntil,
		isNegative:   isNegative,
		rcode:        resp.Rcode,
		ipList:       ExtractIPs(resp),
	}
	entry.lastHitAt.Store(now.UnixNano())

	shard := c.shard(key)
	shard.mu.Lock()
	defer shard.mu.Unlock()

	if old, exists := shard.entries[key]; exists {
		if old.elem != nil {
			shard.lruList.Remove(old.elem)
			old.elem = nil
		}
		delete(shard.entries, key)
	} else if len(shard.entries) >= shard.maxEntries {
		back := shard.lruList.Back()
		if back != nil {
			oldest := back.Value.(*cacheEntry)
			shard.lruList.Remove(back)
			if oldest != nil {
				oldest.elem = nil
				delete(shard.entries, oldest.key)
				c.evictions.Add(1)
			}
		}
	}

	entry.elem = shard.lruList.PushFront(entry)
	shard.entries[key] = entry
	return true
}

// SingleFlight 执行单飞合并并发回源
func (c *DNSCache) SingleFlight(key string, fn func() (*dns.Msg, error)) (*dns.Msg, bool, error) {
	return c.flight.Do(key, fn)
}
