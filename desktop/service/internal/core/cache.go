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
	configMu sync.RWMutex
	config   CacheConfig
	shards   [NumDNSCacheShards]*cacheShard
	// capacityMu 保护 maxEntries：热更新容量时统计/落盘协程会并发读取
	capacityMu sync.RWMutex
	maxEntries int

	flight *singleFlightGroup

	prefetcherMu sync.RWMutex
	prefetcher   Resolver

	// excluder 为域名排除匹配器；nil 或空规则集表示全部缓存
	excluder atomic.Pointer[CacheExcluder]

	// persistMu 保护落盘定时器的启停
	persistMu        sync.Mutex
	persistStop      chan struct{}
	lastPersistError atomic.Value // string

	totalHits     atomic.Uint64
	totalMisses   atomic.Uint64
	staleHits     atomic.Uint64
	negativeHits  atomic.Uint64
	evictions     atomic.Uint64
	prefetchCount atomic.Uint64

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
	if ex, err := NewCacheExcluder(cfg.ExcludePatterns); err == nil {
		c.excluder.Store(ex)
	}
	c.StartPersistLoop()

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

	// 排除规则随之重建。编译失败时保留上一次可用的规则集：
	// 一次笔误不该让已在生效的排除策略整体失效。
	if ex, err := NewCacheExcluder(cfg.ExcludePatterns); err == nil {
		c.excluder.Store(ex)
	} else if len(cfg.ExcludePatterns) == 0 {
		c.excluder.Store(ex)
	}

	// 容量必须同步折算到运行期：只换 config 会让逐出阈值、落盘上限与
	// Stats().MaxEntries 停留在启动值，界面显示"已扩容"而实际毫无变化。
	c.resizeCapacity(cfg.MaxEntries)

	// 落盘开关与间隔都可以在运行时调整。只在启动时判定一次，
	// 会让"刚打开开关却迟迟不落盘"与"已关闭却仍在写盘"两种情形同时出现。
	c.SyncPersistLoop()
}

// SyncPersistLoop 依据当前配置重启定时落盘协程；未开启落盘时确保其处于停止状态
func (c *DNSCache) SyncPersistLoop() {
	c.StopPersistLoop()
	c.StartPersistLoop()
}

// Excluder 返回当前的域名排除匹配器（未配置时返回一个恒不命中的实例）
func (c *DNSCache) Excluder() *CacheExcluder {
	if c == nil {
		return nil
	}
	if ex := c.excluder.Load(); ex != nil {
		return ex
	}
	return &CacheExcluder{}
}

// IsExcluded 判断域名是否被排除在缓存之外
func (c *DNSCache) IsExcluded(domain string) bool {
	return c.Excluder().IsExcluded(domain)
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

// Close 关闭缓存并终止后台主动过期协程。
//
// 关闭前落盘一次：进程正常退出是唯一能确定写盘安全的时机，
// 也让下一次冷启动直接复用热缓存的收益。
func (c *DNSCache) Close() {
	if c.closed.Swap(true) {
		return
	}
	close(c.stopCleaner)
	c.StopPersistLoop()
	c.persistOnShutdown()
}

// StartPersistLoop 在开启落盘时启动定时落盘协程；重复调用无副作用
func (c *DNSCache) StartPersistLoop() {
	cfg := c.GetConfig()
	if !cfg.PersistEnabled || cfg.PersistPath == "" {
		return
	}

	c.persistMu.Lock()
	defer c.persistMu.Unlock()
	if c.persistStop != nil {
		return
	}

	interval := time.Duration(cfg.PersistIntervalSeconds) * time.Second
	if interval <= 0 {
		// 未配置间隔时不做定时落盘，仅在退出时写一次
		return
	}

	stop := make(chan struct{})
	c.persistStop = stop

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-c.stopCleaner:
				return
			case <-ticker.C:
				if err := c.SaveToFile(c.currentPersistPath()); err != nil {
					// 落盘失败不影响服务：缓存本身仍是有效的内存结构
					c.setPersistError(err)
				}
			}
		}
	}()
}

// StopPersistLoop 停止定时落盘协程
func (c *DNSCache) StopPersistLoop() {
	c.persistMu.Lock()
	defer c.persistMu.Unlock()
	if c.persistStop == nil {
		return
	}
	close(c.persistStop)
	c.persistStop = nil
}

// persistOnShutdown 在关闭时落盘一次
func (c *DNSCache) persistOnShutdown() {
	cfg := c.GetConfig()
	if !cfg.PersistEnabled || cfg.PersistPath == "" {
		return
	}
	if err := c.SaveToFile(cfg.PersistPath); err != nil {
		c.setPersistError(err)
	}
}

// currentPersistPath 读取当前生效的落盘路径
func (c *DNSCache) currentPersistPath() string {
	return c.GetConfig().PersistPath
}

// setPersistError 记录最近一次落盘失败原因
func (c *DNSCache) setPersistError(err error) {
	if err == nil {
		return
	}
	c.lastPersistError.Store(err.Error())
}

// LastPersistError 返回最近一次落盘失败的原因（无失败时为空串）
func (c *DNSCache) LastPersistError() string {
	if v, ok := c.lastPersistError.Load().(string); ok {
		return v
	}
	return ""
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
	return c.GetForGroup(req, DefaultClientGroupID)
}

// GetForGroup 按客户端分组查询缓存条目。
//
// group 为默认组时键与 Get 完全一致，未启用分组的部署行为不变。
func (c *DNSCache) GetForGroup(req *dns.Msg, group string) (resp *dns.Msg, hit bool, isStale bool, staleCandidate *cacheEntry) {
	if !c.IsEnabled() || req == nil || len(req.Question) == 0 {
		return nil, false, false, nil
	}

	q := req.Question[0]
	key := CacheKeyForGroup(q.Name, q.Qtype, q.Qclass, group)
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
	return c.PutForGroup(req, resp, DefaultClientGroupID)
}

// PutForGroup 按客户端分组写入缓存条目。
//
// group 为默认组时键与 Put 完全一致，未启用分组的部署行为不变。
func (c *DNSCache) PutForGroup(req *dns.Msg, resp *dns.Msg, group string) bool {
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
	key := CacheKeyForGroup(q.Name, q.Qtype, q.Qclass, group)
	entry := &cacheEntry{
		key:          key,
		group:        normalizeCacheGroup(group),
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

// Remove 从分片缓存中主动剔除指定请求的条目（默认组）。
func (c *DNSCache) Remove(req *dns.Msg) bool {
	return c.RemoveForGroup(req, DefaultClientGroupID)
}

// RemoveForGroup 按客户端分组剔除指定请求的条目。
//
// 分组隔离后条目键带组后缀，只删默认组键会让非默认组的被拦应答
// 一直留到自然过期并持续重放——安全剔除路径必须与写入路径同组。
func (c *DNSCache) RemoveForGroup(req *dns.Msg, group string) bool {
	if req == nil || len(req.Question) == 0 {
		return false
	}
	q := req.Question[0]
	key := CacheKeyForGroup(q.Name, q.Qtype, q.Qclass, group)
	shard := c.shard(key)
	shard.mu.Lock()
	defer shard.mu.Unlock()
	if old, exists := shard.entries[key]; exists {
		if old.elem != nil {
			shard.lruList.Remove(old.elem)
			old.elem = nil
		}
		delete(shard.entries, key)
		return true
	}
	return false
}

// normalizeCacheGroup 把分组名归一化为缓存层使用的形式（空串视为默认组）。
func normalizeCacheGroup(group string) string {
	g := strings.TrimSpace(group)
	if g == "" {
		return DefaultClientGroupID
	}
	return g
}
