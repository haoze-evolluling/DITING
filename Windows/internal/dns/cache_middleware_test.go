package dns

import (
	"context"
	"fmt"
	"net"
	"sync/atomic"
	"testing"

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
	cache := core.NewDNSCache(cacheCfg)
	defer cache.Close()

	resolver := &cacheMockResolver{}
	pipeline := NewPipeline(
		NewCacheMiddleware(cache, resolver),
		NewForwardMiddleware(resolver),
	)

	req := new(dns.Msg)
	req.SetQuestion("swr.local.", dns.TypeA)

	// 预置缓存响应
	preResp := new(dns.Msg)
	preResp.SetReply(req)
	preResp.Answer = []dns.RR{
		&dns.A{
			Hdr: dns.RR_Header{Name: "swr.local.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
			A:   net.ParseIP("10.0.0.1").To4(),
		},
	}
	cache.Put(req, preResp)

	// 将缓存条目人工调整为过期但仍在宽限期内
	_, _, isStale, staleCandidate := cache.Get(req)
	if isStale || staleCandidate != nil {
		t.Fatalf("初始不应为 stale")
	}

	// 触发过期
	cache.UpdateConfig(core.CacheConfig{
		Enabled:              true,
		MaxEntries:           4096,
		Mode:                 "limit_max_ttl",
		MaxTTLSeconds:        3600,
		FixedTTLSeconds:      3600,
		MinTTLEnabled:        false,
		StaleFallbackEnabled: true,
		StaleFallbackSeconds: 300,
		Optimistic:           true,
	})

	// 用 GetEntries 验证存在
	total, items := cache.GetEntries("swr.local", 10)
	if total != 1 || len(items) != 1 {
		t.Fatalf("未能找到预置条目")
	}

	// 执行 SWR 请求
	ctx := NewDNSContext(context.Background(), req, nil, "udp")
	if err := pipeline.Execute(ctx); err != nil {
		t.Fatalf("SWR 执行失败: %v", err)
	}
}

func TestCacheMiddleware_FallbackOnResolverFailure(t *testing.T) {
	cacheCfg := core.DefaultCacheConfig()
	cacheCfg.StaleFallbackEnabled = true
	cacheCfg.StaleFallbackSeconds = 300
	cacheCfg.Optimistic = false // 非乐观模式，先回源
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
			Hdr: dns.RR_Header{Name: "fallback.local.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60},
			A:   net.ParseIP("192.168.1.1").To4(),
		},
	}
	cache.Put(req, initResp)

	// 此时正常命中
	ctx1 := NewDNSContext(context.Background(), req, nil, "udp")
	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("执行失败: %v", err)
	}
	if ctx1.Resp == nil {
		t.Fatalf("应命中响应")
	}
}
