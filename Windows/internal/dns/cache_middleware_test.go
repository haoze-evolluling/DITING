package dns

import (
	"context"
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/miekg/dns"
)

type cacheMockResolver struct {
	calls        atomic.Int32
	responseFunc func(req *dns.Msg) (*dns.Msg, error)
}

func (m *cacheMockResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	m.calls.Add(1)
	if m.responseFunc != nil {
		return m.responseFunc(req)
	}
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Rcode = dns.RcodeSuccess
	rr := &dns.A{
		Hdr: dns.RR_Header{
			Name:   req.Question[0].Name,
			Rrtype: dns.TypeA,
			Class:  dns.ClassINET,
			Ttl:    60,
		},
		A: net.ParseIP("1.2.3.4").To4(),
	}
	resp.Answer = append(resp.Answer, rr)
	return resp, nil
}

func (m *cacheMockResolver) Resolve(ctx context.Context, raw []byte) ([]byte, error) {
	req := new(dns.Msg)
	if err := req.Unpack(raw); err != nil {
		return nil, err
	}
	resp, err := m.Exchange(ctx, req)
	if err != nil {
		return nil, err
	}
	return resp.Pack()
}

func (m *cacheMockResolver) Configure(cfg core.ResolverConfig) error {
	return nil
}

func (m *cacheMockResolver) Shutdown() error {
	return nil
}

func TestCacheMiddleware_MissThenHit(t *testing.T) {
	cacheCfg := core.DefaultCacheConfig()
	cache := core.NewDNSCache(cacheCfg)
	defer cache.Close()

	resolver := &cacheMockResolver{}

	pipeline := NewPipeline(
		NewCacheMiddleware(cache, resolver),
		NewForwardMiddleware(resolver),
	)

	req := new(dns.Msg)
	req.SetQuestion("test.local.", dns.TypeA)

	// 1. 第一次查询：未命中，回源到 resolver
	ctx1 := NewDNSContext(context.Background(), req, nil, "udp")
	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("第一次执行失败: %v", err)
	}

	if ctx1.Resp == nil || len(ctx1.Resp.Answer) != 1 {
		t.Fatalf("第一次查询未得到有效响应")
	}
	if resolver.calls.Load() != 1 {
		t.Fatalf("第一次应调用 1 次 resolver，实际: %d", resolver.calls.Load())
	}

	// 2. 第二次查询：命中新鲜缓存，不应调用 resolver
	ctx2 := NewDNSContext(context.Background(), req, nil, "udp")
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("第二次执行失败: %v", err)
	}

	if ctx2.Resp == nil || len(ctx2.Resp.Answer) != 1 {
		t.Fatalf("第二次查询未从缓存得到有效响应")
	}
	if resolver.calls.Load() != 1 {
		t.Fatalf("第二次命中缓存不应调用 resolver，实际调用次数: %d", resolver.calls.Load())
	}

	hitTag, ok := ctx2.Get("cache_hit")
	if !ok || hitTag != "fresh" {
		t.Fatalf("预期标记 cache_hit 为 fresh，实际: %v", hitTag)
	}
}

func TestCacheMiddleware_OptimisticSWR(t *testing.T) {
	cacheCfg := core.DefaultCacheConfig()
	cacheCfg.Optimistic = true
	cacheCfg.StaleFallbackEnabled = true
	cacheCfg.StaleFallbackSeconds = 300
	cacheCfg.MaxTTLSeconds = 1
	cacheCfg.MinTTLEnabled = false
	cache := core.NewDNSCache(cacheCfg)
	defer cache.Close()

	resolver := &cacheMockResolver{}
	pipeline := NewPipeline(
		NewCacheMiddleware(cache, resolver),
		NewForwardMiddleware(resolver),
	)

	req := new(dns.Msg)
	req.SetQuestion("swr.local.", dns.TypeA)

	// 预置缓存响应 (TTL=1)
	preResp := new(dns.Msg)
	preResp.SetReply(req)
	preResp.Answer = []dns.RR{
		&dns.A{
			Hdr: dns.RR_Header{Name: "swr.local.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 1},
			A:   net.ParseIP("10.0.0.1").To4(),
		},
	}
	cache.Put(req, preResp)

	// 等待 1.1s 确保条目真实过期进入 Stale 宽限期
	time.Sleep(1100 * time.Millisecond)

	// 确认此时已是 Stale 候选状态
	_, hit, isStale, staleCandidate := cache.Get(req)
	if hit || !isStale || staleCandidate == nil {
		t.Fatalf("条目应当已过期并处于 Stale 状态: hit=%v, isStale=%v", hit, isStale)
	}

	// 执行 SWR 请求：应当乐观返回 Stale 响应 (TTL=1)，并在后台异步刷新
	ctx := NewDNSContext(context.Background(), req, nil, "udp")
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("SWR 执行失败: %v", err)
	}

	if ctx.Resp == nil || len(ctx.Resp.Answer) == 0 {
		t.Fatalf("SWR 应当返回有效响应")
	}
	if ctx.Resp.Answer[0].Header().Ttl != 1 {
		t.Fatalf("SWR 响应的 TTL 必须重写为 1，实际: %d", ctx.Resp.Answer[0].Header().Ttl)
	}
	hitTag, ok := ctx.Get("cache_hit")
	if !ok || hitTag != "stale" {
		t.Fatalf("预期标记 cache_hit 为 stale，实际: %v", hitTag)
	}

	// 等待后台异步刷新完成
	time.Sleep(100 * time.Millisecond)
	if resolver.calls.Load() != 1 {
		t.Fatalf("后台异步刷新应触发 1 次上游调用，实际: %d", resolver.calls.Load())
	}
}

func TestCacheMiddleware_FallbackOnResolverFailure(t *testing.T) {
	cacheCfg := core.DefaultCacheConfig()
	cacheCfg.StaleFallbackEnabled = true
	cacheCfg.StaleFallbackSeconds = 300
	cacheCfg.Optimistic = false // 非乐观模式：过期后先向上游回源
	cacheCfg.MaxTTLSeconds = 1
	cacheCfg.MinTTLEnabled = false
	cache := core.NewDNSCache(cacheCfg)
	defer cache.Close()

	failResolver := &cacheMockResolver{
		responseFunc: func(req *dns.Msg) (*dns.Msg, error) {
			return nil, fmt.Errorf("upstream timeout")
		},
	}

	pipeline := NewPipeline(
		NewCacheMiddleware(cache, failResolver),
		NewForwardMiddleware(failResolver),
	)

	req := new(dns.Msg)
	req.SetQuestion("fallback.local.", dns.TypeA)

	// 预先存入条目
	initResp := new(dns.Msg)
	initResp.SetReply(req)
	initResp.Answer = []dns.RR{
		&dns.A{
			Hdr: dns.RR_Header{Name: "fallback.local.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 1},
			A:   net.ParseIP("192.168.1.1").To4(),
		},
	}
	cache.Put(req, initResp)

	// 等待 1.1s 确保条目真正过期
	time.Sleep(1100 * time.Millisecond)

	// 执行请求：上游回源失败，应降级 fallback 到 Stale 缓存返回
	ctx := NewDNSContext(context.Background(), req, nil, "udp")
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("上游失败时应降级使用 Stale 响应，而非报错: %v", err)
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) == 0 {
		t.Fatalf("应当获取到降级 Stale 响应")
	}
	if ctx.Resp.Answer[0].Header().Ttl != 1 {
		t.Fatalf("降级响应的 TTL 必须重写为 1，实际: %d", ctx.Resp.Answer[0].Header().Ttl)
	}
	hitTag, ok := ctx.Get("cache_hit")
	if !ok || hitTag != "stale_fallback" {
		t.Fatalf("预期标记 cache_hit 为 stale_fallback，实际: %v", hitTag)
	}
}

func TestCacheMiddleware_SingleFlightUncacheableShared(t *testing.T) {
	cacheCfg := core.DefaultCacheConfig()
	cacheCfg.MinTTLEnabled = false // 允许 TTL=0 不入缓存
	cache := core.NewDNSCache(cacheCfg)
	defer cache.Close()

	var upstreamCalls atomic.Int32
	resolver := &cacheMockResolver{
		responseFunc: func(req *dns.Msg) (*dns.Msg, error) {
			upstreamCalls.Add(1)
			time.Sleep(30 * time.Millisecond) // 模拟上游耗时
			resp := new(dns.Msg)
			resp.SetReply(req)
			resp.Answer = []dns.RR{
				&dns.A{
					Hdr: dns.RR_Header{Name: req.Question[0].Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 0},
					A:   net.ParseIP("9.9.9.9").To4(),
				},
			}
			return resp, nil
		},
	}

	pipeline := NewPipeline(
		NewCacheMiddleware(cache, resolver),
		NewForwardMiddleware(resolver),
	)

	req1 := new(dns.Msg)
	req1.SetQuestion("zero-ttl.local.", dns.TypeA)
	req1.Id = 1001

	req2 := new(dns.Msg)
	req2.SetQuestion("zero-ttl.local.", dns.TypeA)
	req2.Id = 1002

	// 并发执行两个相同查询
	var wg sync.WaitGroup
	ctx1 := NewDNSContext(context.Background(), req1, nil, "udp")
	ctx2 := NewDNSContext(context.Background(), req2, nil, "udp")

	wg.Add(2)
	go func() {
		defer wg.Done()
		_ = pipeline.Execute(ctx1)
	}()
	go func() {
		defer wg.Done()
		time.Sleep(5 * time.Millisecond) // 确保让 ctx1 先进入 SingleFlight
		_ = pipeline.Execute(ctx2)
	}()
	wg.Wait()

	if upstreamCalls.Load() != 1 {
		t.Fatalf("SingleFlight 应合并为 1 次上游调用，实际: %d", upstreamCalls.Load())
	}
	if ctx1.Resp == nil || len(ctx1.Resp.Answer) == 0 {
		t.Fatalf("请求 1 未获取到有效响应")
	}
	if ctx2.Resp == nil || len(ctx2.Resp.Answer) == 0 {
		t.Fatalf("请求 2 (共享等待者) 未获取到有效响应，遭遇丢包或 SERVFAIL")
	}
	if ctx2.Resp.Id != 1002 {
		t.Fatalf("请求 2 响应 ID 未正确匹配客户端请求 ID: %d", ctx2.Resp.Id)
	}
}
