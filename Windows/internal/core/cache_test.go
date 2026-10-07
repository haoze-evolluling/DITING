package core

import (
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func createTestQuery(name string, qtype uint16) *dns.Msg {
	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(name), qtype)
	m.RecursionDesired = true
	return m
}

func createTestResponse(name string, qtype uint16, ipStr string, ttl uint32) *dns.Msg {
	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(name), qtype)
	m.Response = true
	m.Rcode = dns.RcodeSuccess
	rr := &dns.A{
		Hdr: dns.RR_Header{
			Name:   dns.Fqdn(name),
			Rrtype: dns.TypeA,
			Class:  dns.ClassINET,
			Ttl:    ttl,
		},
		A: net.ParseIP(ipStr).To4(),
	}
	m.Answer = append(m.Answer, rr)
	return m
}

func createNegativeResponse(name string, qtype uint16, soaTTL uint32) *dns.Msg {
	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(name), qtype)
	m.Response = true
	m.Rcode = dns.RcodeNameError
	soa := &dns.SOA{
		Hdr: dns.RR_Header{
			Name:   dns.Fqdn("example.com"),
			Rrtype: dns.TypeSOA,
			Class:  dns.ClassINET,
			Ttl:    soaTTL,
		},
		Ns:     "ns.example.com.",
		Mbox:   "hostmaster.example.com.",
		Serial: 1,
		Minttl: soaTTL,
	}
	m.Ns = append(m.Ns, soa)
	return m
}

func TestDNSCache_BasicPutAndGet(t *testing.T) {
	cfg := DefaultCacheConfig()
	cfg.MaxTTLSeconds = 300
	cache := NewDNSCache(cfg)
	defer cache.Close()

	req := createTestQuery("example.com", dns.TypeA)
	resp := createTestResponse("example.com", dns.TypeA, "93.184.216.34", 120)

	// 初始查询未命中
	_, hit, isStale, _ := cache.Get(req)
	if hit || isStale {
		t.Fatalf("预期初始查询未命中，但 hit=%v, isStale=%v", hit, isStale)
	}

	// 存入缓存
	if !cache.Put(req, resp) {
		t.Fatalf("Put 返回失败")
	}

	// 再次查询新鲜命中
	hitResp, hit, isStale, _ := cache.Get(req)
	if !hit || isStale || hitResp == nil {
		t.Fatalf("预期命中新鲜缓存，实际 hit=%v, isStale=%v", hit, isStale)
	}

	if len(hitResp.Answer) != 1 {
		t.Fatalf("应包含 1 条 Answer 记录，实际包含 %d 条", len(hitResp.Answer))
	}

	// 检查 TTL 重写机制 (应当递减且有效)
	if hitResp.Answer[0].Header().Ttl <= 0 || hitResp.Answer[0].Header().Ttl > 120 {
		t.Fatalf("重写的 TTL 异常: %d", hitResp.Answer[0].Header().Ttl)
	}

	stats := cache.Stats()
	if stats.TotalHits != 1 || stats.TotalMisses != 1 {
		t.Fatalf("命中指标异常: hits=%d, misses=%d", stats.TotalHits, stats.TotalMisses)
	}
}

func TestDNSCache_64ShardsDistribution(t *testing.T) {
	cfg := DefaultCacheConfig()
	cache := NewDNSCache(cfg)
	defer cache.Close()

	// 写入多个不同域名
	count := 256
	for i := 0; i < count; i++ {
		domain := fmt.Sprintf("host-%d.diting.internal", i)
		req := createTestQuery(domain, dns.TypeA)
		resp := createTestResponse(domain, dns.TypeA, "10.0.0.1", 60)
		cache.Put(req, resp)
	}

	stats := cache.Stats()
	if stats.EntryCount != count {
		t.Fatalf("预期条目数 %d，实际 %d", count, stats.EntryCount)
	}

	// 验证条目分散在多个分片中，而不是全部挤在一个分片
	activeShards := 0
	for _, shard := range cache.shards {
		shard.mu.RLock()
		if len(shard.entries) > 0 {
			activeShards++
		}
		shard.mu.RUnlock()
	}

	if activeShards < 30 {
		t.Fatalf("哈希分片分散不均，仅有 %d/64 分片被使用", activeShards)
	}
}

func TestDNSCache_LRUEviction(t *testing.T) {
	cfg := DefaultCacheConfig()
	// 设置极小的容量测试淘汰 (每分片容量 = 64/64 = 1)
	cfg.MaxEntries = 64
	cache := NewDNSCache(cfg)
	defer cache.Close()

	// 构造会导致命中同一个分片的两个 key
	key1Domain := "a.test"
	key2Domain := "b.test"
	// 找到两个哈希到同一分片的域名
	targetShardIdx := fnv32(CacheKey(key1Domain, dns.TypeA, dns.ClassINET)) % NumDNSCacheShards
	found := false
	for i := 0; i < 10000; i++ {
		candidate := fmt.Sprintf("domain-%d.test", i)
		if fnv32(CacheKey(candidate, dns.TypeA, dns.ClassINET))%NumDNSCacheShards == targetShardIdx {
			key2Domain = candidate
			found = true
			break
		}
	}
	if !found {
		t.Skip("未能构造同分片碰撞域名")
	}

	req1 := createTestQuery(key1Domain, dns.TypeA)
	resp1 := createTestResponse(key1Domain, dns.TypeA, "1.1.1.1", 60)

	req2 := createTestQuery(key2Domain, dns.TypeA)
	resp2 := createTestResponse(key2Domain, dns.TypeA, "2.2.2.2", 60)

	cache.Put(req1, resp1)
	// 此时 key1 应存在
	if _, hit, _, _ := cache.Get(req1); !hit {
		t.Fatalf("key1 应命中")
	}

	// 存入 key2，由于分片上限为 1，应淘汰 key1
	cache.Put(req2, resp2)

	// key2 应命中
	if _, hit, _, _ := cache.Get(req2); !hit {
		t.Fatalf("key2 应命中")
	}

	// key1 应已被淘汰
	if _, hit, _, _ := cache.Get(req1); hit {
		t.Fatalf("key1 应已被 LRU 淘汰")
	}

	if cache.Stats().EvictionCount < 1 {
		t.Fatalf("应记录至少 1 次淘汰")
	}
}

func TestDNSCache_TTLPolicyModes(t *testing.T) {
	// 1. Limit Max TTL 测试
	cfgLimit := DefaultCacheConfig()
	cfgLimit.Mode = "limit_max_ttl"
	cfgLimit.MaxTTLSeconds = 100
	cacheLimit := NewDNSCache(cfgLimit)
	defer cacheLimit.Close()

	req := createTestQuery("limit.com", dns.TypeA)
	resp := createTestResponse("limit.com", dns.TypeA, "1.1.1.1", 1000)
	cacheLimit.Put(req, resp)

	hitResp, hit, _, _ := cacheLimit.Get(req)
	if !hit || hitResp.Answer[0].Header().Ttl > 100 {
		t.Fatalf("limit_max_ttl 应裁剪上游 TTL 至 100，实际: %d", hitResp.Answer[0].Header().Ttl)
	}

	// 2. Fixed TTL 测试
	cfgFixed := DefaultCacheConfig()
	cfgFixed.Mode = "fixed_ttl"
	cfgFixed.FixedTTLSeconds = 50
	cacheFixed := NewDNSCache(cfgFixed)
	defer cacheFixed.Close()

	reqFixed := createTestQuery("fixed.com", dns.TypeA)
	respFixed := createTestResponse("fixed.com", dns.TypeA, "1.1.1.1", 300)
	cacheFixed.Put(reqFixed, respFixed)

	hitFixed, hit, _, _ := cacheFixed.Get(reqFixed)
	if !hit || hitFixed.Answer[0].Header().Ttl > 50 {
		t.Fatalf("fixed_ttl 应固定 TTL 为 50，实际: %d", hitFixed.Answer[0].Header().Ttl)
	}

	// 3. Min TTL 保障测试
	cfgMin := DefaultCacheConfig()
	cfgMin.MinTTLEnabled = true
	cfgMin.MinTTLSeconds = 45
	cacheMin := NewDNSCache(cfgMin)
	defer cacheMin.Close()

	reqMin := createTestQuery("min.com", dns.TypeA)
	respMin := createTestResponse("min.com", dns.TypeA, "1.1.1.1", 5) // 上游仅给 5 秒
	cacheMin.Put(reqMin, respMin)

	hitMin, hit, _, _ := cacheMin.Get(reqMin)
	if !hit || hitMin.Answer[0].Header().Ttl < 40 {
		t.Fatalf("min_ttl 机制应拉升 TTL 至至少 45，实际: %d", hitMin.Answer[0].Header().Ttl)
	}
}

func TestDNSCache_NegativeCaching(t *testing.T) {
	cfg := DefaultCacheConfig()
	cfg.NegativeTTLEnabled = true
	cfg.NegativeTTLSeconds = 20
	cache := NewDNSCache(cfg)
	defer cache.Close()

	req := createTestQuery("not-exist-domain.invalid", dns.TypeA)
	resp := createNegativeResponse("not-exist-domain.invalid", dns.TypeA, 15)

	cache.Put(req, resp)

	hitResp, hit, isStale, _ := cache.Get(req)
	if !hit || isStale || hitResp == nil {
		t.Fatalf("负缓存未成功命中")
	}

	if hitResp.Rcode != dns.RcodeNameError {
		t.Fatalf("负缓存响应码应为 NXDOMAIN，实际: %d", hitResp.Rcode)
	}

	if cache.Stats().NegativeHits != 1 {
		t.Fatalf("负缓存命中计数异常: %d", cache.Stats().NegativeHits)
	}
}

func TestDNSCache_StaleWhileRevalidate(t *testing.T) {
	cfg := DefaultCacheConfig()
	cfg.StaleFallbackEnabled = true
	cfg.StaleFallbackSeconds = 300
	cfg.Optimistic = true
	cache := NewDNSCache(cfg)
	defer cache.Close()

	req := createTestQuery("swr.test", dns.TypeA)
	resp := createTestResponse("swr.test", dns.TypeA, "1.1.1.1", 60)

	cache.Put(req, resp)

	// 人工将 entry 过期时间调整为过去，但仍在 staleUntil 宽限期内
	key := CacheKey("swr.test", dns.TypeA, dns.ClassINET)
	shard := cache.shard(key)
	shard.mu.Lock()
	entry := shard.entries[key]
	entry.expiresAt = time.Now().Add(-10 * time.Second)
	entry.staleUntil = time.Now().Add(200 * time.Second)
	shard.mu.Unlock()

	// 此时 Get 应识别为 staleCandidate
	_, hit, isStale, staleCandidate := cache.Get(req)
	if hit || !isStale || staleCandidate == nil {
		t.Fatalf("过期条目在宽限期内应识别为 staleCandidate: hit=%v, isStale=%v", hit, isStale)
	}

	// 构造 SWR 响应
	staleResp := cache.BuildStaleResponse(req, staleCandidate)
	if staleResp == nil {
		t.Fatalf("BuildStaleResponse 失败")
	}

	if staleResp.Answer[0].Header().Ttl != 1 {
		t.Fatalf("SWR 陈旧响应的 TTL 应重写为 1，实际: %d", staleResp.Answer[0].Header().Ttl)
	}

	if cache.Stats().StaleHits != 1 {
		t.Fatalf("StaleHits 计数异常: %d", cache.Stats().StaleHits)
	}
}

func TestDNSCache_SingleFlightCoalescing(t *testing.T) {
	cfg := DefaultCacheConfig()
	cache := NewDNSCache(cfg)
	defer cache.Close()

	key := CacheKey("concurrent.test", dns.TypeA, dns.ClassINET)

	var callCount atomic.Int32
	var wg sync.WaitGroup

	concurrentReqs := 20
	results := make([]*dns.Msg, concurrentReqs)

	for i := 0; i < concurrentReqs; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			val, _, err := cache.SingleFlight(key, func() (*dns.Msg, error) {
				callCount.Add(1)
				time.Sleep(30 * time.Millisecond) // 模拟上游耗时
				return createTestResponse("concurrent.test", dns.TypeA, "1.2.3.4", 60), nil
			})
			if err == nil {
				results[idx] = val
			}
		}(i)
	}

	wg.Wait()

	if callCount.Load() != 1 {
		t.Fatalf("SingleFlight 应合并并发请求，实际回源调用次数: %d", callCount.Load())
	}

	for i, res := range results {
		if res == nil || len(res.Answer) == 0 {
			t.Fatalf("结果 [%d] 解析异常为空", i)
		}
	}
}

func TestDNSCache_SearchAndTopDomains(t *testing.T) {
	cfg := DefaultCacheConfig()
	cache := NewDNSCache(cfg)
	defer cache.Close()

	reqA := createTestQuery("bing.com", dns.TypeA)
	respA := createTestResponse("bing.com", dns.TypeA, "1.1.1.1", 60)
	cache.Put(reqA, respA)

	reqB := createTestQuery("google.com", dns.TypeA)
	respB := createTestResponse("google.com", dns.TypeA, "8.8.8.8", 60)
	cache.Put(reqB, respB)

	// 模拟 bing.com 多次命中
	cache.Get(reqA)
	cache.Get(reqA)
	cache.Get(reqA)

	// 检索
	total, items := cache.GetEntries("bing", 10)
	if total != 1 || len(items) != 1 || items[0].Domain != "bing.com" {
		t.Fatalf("检索 bing.com 失败: total=%d, items=%v", total, items)
	}

	// 排行榜
	tops := cache.GetTopDomains(5)
	if len(tops) < 2 {
		t.Fatalf("Top 域名数量不足: %d", len(tops))
	}
	if tops[0].Domain != "bing.com" || tops[0].HitCount < 3 {
		t.Fatalf("Top 1 应为 bing.com，实际: %s, hits: %d", tops[0].Domain, tops[0].HitCount)
	}
}

func TestDNSCache_ClearAndClose(t *testing.T) {
	cfg := DefaultCacheConfig()
	cache := NewDNSCache(cfg)

	req := createTestQuery("clear.test", dns.TypeA)
	resp := createTestResponse("clear.test", dns.TypeA, "1.1.1.1", 60)
	cache.Put(req, resp)

	if cache.Stats().EntryCount != 1 {
		t.Fatalf("存入后应有 1 个条目")
	}

	cache.Clear()
	if cache.Stats().EntryCount != 0 {
		t.Fatalf("清空后条目数应为 0")
	}

	cache.Close()
	// 重复 Close 安全性
	cache.Close()
}
