package querylog

import (
	"sort"
	"sync"
	"time"
)

// 统计窗口与容量约束。
const (
	// statsWindowHours 滚动统计窗口（小时）
	statsWindowHours = 24
	// statsMaxKeysPerHour 单个小时内 Top 名单追踪的去重键上限，防止热点探测导致内存膨胀
	statsMaxKeysPerHour = 10000
)

// bucket 单个小时的聚合桶。
type bucket struct {
	hourMs    int64
	queries   int
	blocked   int
	cached    int
	forwarded int
	errors    int
	latSumMs  float64

	topDomains map[string]int
	topBlocked map[string]int
	topClients map[string]int
}

func newBucket(hourMs int64) *bucket {
	return &bucket{
		hourMs:     hourMs,
		topDomains: make(map[string]int),
		topBlocked: make(map[string]int),
		topClients: make(map[string]int),
	}
}

// incMap 在受限的 Top 名单中自增计数，超过键上限时忽略新键。
func incMap(m map[string]int, key string) {
	if key == "" {
		return
	}
	if _, ok := m[key]; !ok && len(m) >= statsMaxKeysPerHour {
		return
	}
	m[key]++
}

// Collector 24 小时滚动按小时聚合的统计收集器，线程安全。
// 设计借鉴自 blocky (stats/collector.go)。
type Collector struct {
	mu      sync.RWMutex
	buckets map[int64]*bucket
	now     func() time.Time
}

// NewCollector 创建统计收集器。
func NewCollector() *Collector {
	return &Collector{
		buckets: make(map[int64]*bucket),
		now:     time.Now,
	}
}

// hourKey 将 Unix 毫秒规整为所在小时的起点（本地时区，便于 UI 展示）。
func hourKey(ms int64) int64 {
	t := time.UnixMilli(ms)
	return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), 0, 0, 0, t.Location()).UnixMilli()
}

// Record 将一条查询记录计入对应小时桶，并顺带清理超出窗口的旧桶。
func (c *Collector) Record(r Record) {
	if c == nil || r.Timestamp <= 0 {
		return
	}
	key := hourKey(r.Timestamp)

	c.mu.Lock()
	defer c.mu.Unlock()

	b, ok := c.buckets[key]
	if !ok {
		b = newBucket(key)
		c.buckets[key] = b
		c.evictLocked()
	}

	b.queries++
	b.latSumMs += r.DurationMs

	switch NormalizeStatus(r.Status) {
	case StatusBlocked:
		b.blocked++
	case StatusCached, StatusStale:
		b.cached++
	case StatusError:
		b.errors++
	default:
		if !r.Blocked {
			b.forwarded++
		}
	}
	if r.Blocked && NormalizeStatus(r.Status) != StatusBlocked {
		b.blocked++
	}

	incMap(b.topDomains, r.Domain)
	if r.Blocked {
		incMap(b.topBlocked, r.Domain)
	}
	client := r.ClientName
	if client == "" {
		client = r.ClientIP
	}
	incMap(b.topClients, client)
}

// evictLocked 清理超出统计窗口的桶。调用方须持有写锁。
func (c *Collector) evictLocked() {
	if len(c.buckets) <= statsWindowHours+1 {
		return
	}
	cutoff := hourKey(c.now().Add(-time.Duration(statsWindowHours+1) * time.Hour).UnixMilli())
	for k := range c.buckets {
		if k < cutoff {
			delete(c.buckets, k)
		}
	}
}

// windowBucketsLocked 返回落在最近 24 小时窗口内的桶。调用方须持有读锁。
func (c *Collector) windowBucketsLocked() []*bucket {
	cutoff := hourKey(c.now().Add(-time.Duration(statsWindowHours-1) * time.Hour).UnixMilli())
	out := make([]*bucket, 0, statsWindowHours)
	for k, b := range c.buckets {
		if k >= cutoff {
			out = append(out, b)
		}
	}
	return out
}

// Summary 生成当前 24 小时滚动窗口的汇总统计。
func (c *Collector) Summary() Summary {
	if c == nil {
		return Summary{}
	}
	c.mu.RLock()
	defer c.mu.RUnlock()

	var s Summary
	var latSum float64
	for _, b := range c.windowBucketsLocked() {
		s.Queries += b.queries
		s.Blocked += b.blocked
		s.Cached += b.cached
		s.Forwarded += b.forwarded
		s.Errors += b.errors
		latSum += b.latSumMs
	}
	if s.Queries > 0 {
		s.AvgResponseMs = latSum / float64(s.Queries)
		denom := s.Queries - s.Errors
		if denom > 0 {
			s.CacheHitRate = float64(s.Cached) / float64(denom)
		} else {
			s.CacheHitRate = float64(s.Cached) / float64(s.Queries)
		}
	}
	return s
}

// PerHour 返回最近 24 小时的逐小时数据点（无数据的小时补零）。
func (c *Collector) PerHour() []HourPoint {
	if c == nil {
		return nil
	}
	c.mu.RLock()
	defer c.mu.RUnlock()

	byKey := make(map[int64]*bucket)
	for _, b := range c.windowBucketsLocked() {
		byKey[b.hourMs] = b
	}

	points := make([]HourPoint, 0, statsWindowHours)
	start := hourKey(c.now().Add(-time.Duration(statsWindowHours-1) * time.Hour).UnixMilli())
	for i := 0; i < statsWindowHours; i++ {
		key := start + int64(i)*int64(time.Hour/time.Millisecond)
		p := HourPoint{HourMs: key}
		if b, ok := byKey[key]; ok {
			p.Queries = b.queries
			p.Blocked = b.blocked
			p.Cached = b.cached
		}
		points = append(points, p)
	}
	return points
}

// TopDomains 返回窗口内访问量最高的域名排行。
func (c *Collector) TopDomains(n int) []NameCount {
	return c.topN(n, func(b *bucket) map[string]int { return b.topDomains })
}

// TopBlockedDomains 返回窗口内被拦截次数最高的域名排行。
func (c *Collector) TopBlockedDomains(n int) []NameCount {
	return c.topN(n, func(b *bucket) map[string]int { return b.topBlocked })
}

// TopClients 返回窗口内查询量最高的客户端排行。
func (c *Collector) TopClients(n int) []NameCount {
	return c.topN(n, func(b *bucket) map[string]int { return b.topClients })
}

// topN 聚合窗口内指定名单并返回降序前 n 项。
func (c *Collector) topN(n int, pick func(*bucket) map[string]int) []NameCount {
	if c == nil || n <= 0 {
		return nil
	}
	c.mu.RLock()
	agg := make(map[string]int)
	for _, b := range c.windowBucketsLocked() {
		for k, v := range pick(b) {
			agg[k] += v
		}
	}
	c.mu.RUnlock()

	list := make([]NameCount, 0, len(agg))
	for k, v := range agg {
		list = append(list, NameCount{Name: k, Count: v})
	}
	sort.Slice(list, func(i, j int) bool {
		if list[i].Count != list[j].Count {
			return list[i].Count > list[j].Count
		}
		return list[i].Name < list[j].Name
	})
	if len(list) > n {
		list = list[:n]
	}
	return list
}

// Clear 清空全部统计桶。
func (c *Collector) Clear() {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.buckets = make(map[int64]*bucket)
}
