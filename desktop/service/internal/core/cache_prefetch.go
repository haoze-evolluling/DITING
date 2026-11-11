package core

import (
	"context"
	"time"

	"github.com/miekg/dns"
)

// 主动预取相关常量。
const (
	// defaultPrefetchThreshold 默认命中次数门槛，低于该值的条目不参与预取
	defaultPrefetchThreshold = 5
	// defaultPrefetchBeforeMs 默认剩余有效期阈值（毫秒），低于该值触发预取
	defaultPrefetchBeforeMs = int64(30000)
	// maxPrefetchBeforeMs 剩余有效期阈值的上限
	maxPrefetchBeforeMs = int64(3600_000)
	// maxPrefetchPerTick 单次后台巡检最多刷新的条目数，防止上游被瞬时打满
	maxPrefetchPerTick = 64
	// prefetchMinInterval 同一键的最短二次刷新间隔护栏（刷新失败时避免高频重试）
	prefetchMinInterval = 5 * time.Second
)

// SetPrefetcher 接线回源解析器，供后台热点预取使用。
//
// 传入 nil 即关闭预取回源能力（配置开关仍独立生效）。
func (c *DNSCache) SetPrefetcher(res Resolver) {
	if c == nil {
		return
	}
	c.prefetcherMu.Lock()
	c.prefetcher = res
	c.prefetcherMu.Unlock()
}

// prefetcherRef 读取当前回源解析器引用。
func (c *DNSCache) prefetcherRef() Resolver {
	if c == nil {
		return nil
	}
	c.prefetcherMu.RLock()
	defer c.prefetcherMu.RUnlock()
	return c.prefetcher
}

// IsPrefetchEnabled 检查主动预取是否处于启用状态。
func (c *DNSCache) IsPrefetchEnabled() bool {
	if c == nil {
		return false
	}
	c.configMu.RLock()
	defer c.configMu.RUnlock()
	return c.config.Enabled && c.config.PrefetchEnabled
}

// PrefetchCount 返回累计成功预取刷新次数。
func (c *DNSCache) PrefetchCount() uint64 {
	if c == nil {
		return 0
	}
	return c.prefetchCount.Load()
}

// buildPrefetchRequest 由缓存条目重建等价的标准查询请求。
func (e *cacheEntry) buildPrefetchRequest() *dns.Msg {
	if e == nil || e.domain == "" {
		return nil
	}
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(e.domain), e.qtype)
	if len(req.Question) > 0 {
		req.Question[0].Qclass = e.qclass
	}
	return req
}

// prefetchHotEntries 扫描各分片，对"临近过期且足够热门"的条目主动回源刷新。
//
// 设计借鉴 blocky cache/prefetching 与 Technitium ResolverPrefetchDnsCache：
// 复用既有 cacheEntry.hitCount 判定热度与 SingleFlight 去重，不引入额外计数结构。
func (c *DNSCache) prefetchHotEntries(now time.Time) {
	if c == nil {
		return
	}
	cfg := c.GetConfig()
	if !cfg.Enabled || !cfg.PrefetchEnabled {
		return
	}
	res := c.prefetcherRef()
	if res == nil {
		return
	}

	threshold := uint64(cfg.PrefetchThreshold)
	if threshold == 0 {
		threshold = defaultPrefetchThreshold
	}
	before := time.Duration(cfg.PrefetchBeforeExpiryMs) * time.Millisecond
	if before <= 0 {
		before = time.Duration(defaultPrefetchBeforeMs) * time.Millisecond
	}

	candidates := c.collectPrefetchCandidates(now, threshold, before)
	for _, e := range candidates {
		// 标记刷新时间，失败时由 prefetchMinInterval 护栏抑制重复回源
		e.lastPrefetchAt.Store(now.UnixNano())

		req := e.buildPrefetchRequest()
		if req == nil {
			continue
		}
		// 条目键带分组后缀，回源与写回都必须落在同一分组：
		// 用默认组回源会把结果写到别的键上（分组热点永不刷新），
		// 还会让默认组凭空多出非默认组流量触发的条目。
		group := e.group
		if group == "" {
			group = DefaultClientGroupID
		}
		_, _, err := c.flight.Do(e.key, func() (*dns.Msg, error) {
			resp, exErr := exchangeForPrefetch(res, group, req)
			if exErr == nil && resp != nil {
				c.PutForGroup(req, resp, group)
			}
			return resp, exErr
		})
		if err == nil {
			c.prefetchCount.Add(1)
		}
	}
}

// groupResolver 供预取按分组回源的解析器能力（*CoreResolver 实现）。
type groupResolver interface {
	ExchangeForGroup(ctx context.Context, group string, req *dns.Msg) (*dns.Msg, error)
}

// exchangeForPrefetch 按条目所属分组回源；非默认组优先走分组专属上游，
// 解析器不支持分组或分组为默认组时回落全局解析。
func exchangeForPrefetch(res Resolver, group string, req *dns.Msg) (*dns.Msg, error) {
	if group != DefaultClientGroupID {
		if gr, ok := res.(groupResolver); ok {
			return gr.ExchangeForGroup(context.Background(), group, req)
		}
	}
	return res.Exchange(context.Background(), req)
}

// collectPrefetchCandidates 收集符合预取条件的条目（至多 maxPrefetchPerTick 个）。
func (c *DNSCache) collectPrefetchCandidates(now time.Time, threshold uint64, before time.Duration) []*cacheEntry {
	var candidates []*cacheEntry
	for _, shard := range c.shards {
		shard.mu.RLock()
		for _, e := range shard.entries {
			if e == nil || e.isNegative {
				continue
			}
			// 仅在新鲜期内预取；已过期者交由 SWR 容灾链路处理
			if !now.Before(e.expiresAt) {
				continue
			}
			if e.expiresAt.Sub(now) > before {
				continue
			}
			if e.hitCount.Load() < threshold {
				continue
			}
			if last := e.lastPrefetchAt.Load(); last > 0 && now.Sub(time.Unix(0, last)) < prefetchMinInterval {
				continue
			}
			candidates = append(candidates, e)
		}
		shard.mu.RUnlock()
		if len(candidates) >= maxPrefetchPerTick {
			break
		}
	}
	if len(candidates) > maxPrefetchPerTick {
		candidates = candidates[:maxPrefetchPerTick]
	}
	return candidates
}
