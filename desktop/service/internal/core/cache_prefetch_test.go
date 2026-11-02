package core

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"
)

// fakePrefetchResolver 记录回源次数的假解析器。
type fakePrefetchResolver struct {
	mu    sync.Mutex
	calls int
	ttl   uint32

	entered chan struct{} // 非 nil 时在回源前发出信号
	release chan struct{} // 非 nil 时在回源前等待该信号
}

func (f *fakePrefetchResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	f.mu.Lock()
	f.calls++
	ttl := f.ttl
	entered, release := f.entered, f.release
	f.mu.Unlock()

	if entered != nil {
		entered <- struct{}{}
	}
	if release != nil {
		<-release
	}

	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Response = true
	if len(req.Question) > 0 {
		resp.Answer = append(resp.Answer, &dns.A{
			Hdr: dns.RR_Header{Name: req.Question[0].Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: ttl},
			A:   []byte{1, 2, 3, 4},
		})
	}
	return resp, nil
}

func (f *fakePrefetchResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	return nil, nil
}
func (f *fakePrefetchResolver) Configure(cfg ResolverConfig) error { return nil }
func (f *fakePrefetchResolver) Shutdown() error                    { return nil }

func (f *fakePrefetchResolver) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

// prefetchTestCache 构造一个启用了预取、TTL 完全跟随上游的缓存。
func prefetchTestCache(t *testing.T) *DNSCache {
	t.Helper()
	cfg := DefaultCacheConfig()
	cfg.MinTTLEnabled = false
	cfg.Mode = "follow_dns_ttl"
	cfg.PrefetchEnabled = true
	cfg.PrefetchThreshold = 3
	c := NewDNSCache(cfg)
	t.Cleanup(c.Close)
	return c
}

// putHotEntry 写入一个临近过期的热点条目并累计命中次数。
func putHotEntry(t *testing.T, c *DNSCache, domain string, ttl uint32, hits int) *dns.Msg {
	t.Helper()
	req := new(dns.Msg)
	req.SetQuestion(dns.Fqdn(domain), dns.TypeA)

	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Answer = append(resp.Answer, &dns.A{
		Hdr: dns.RR_Header{Name: req.Question[0].Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: ttl},
		A:   []byte{9, 9, 9, 9},
	})
	if !c.Put(req, resp) {
		t.Fatalf("Put(%s) failed", domain)
	}
	for i := 0; i < hits; i++ {
		if _, hit, _, _ := c.Get(req); !hit {
			t.Fatalf("expected fresh hit while warming %s", domain)
		}
	}
	return req
}

func TestPrefetchRefreshesHotNearExpiryEntry(t *testing.T) {
	c := prefetchTestCache(t)
	res := &fakePrefetchResolver{ttl: 10}
	c.SetPrefetcher(res)

	// TTL=10s < 默认 30s 预取窗口，命中 3 次达到门槛
	putHotEntry(t, c, "hot.com", 10, 3)

	c.prefetchHotEntries(time.Now())

	if got := res.callCount(); got != 1 {
		t.Fatalf("expected exactly 1 upstream exchange, got %d", got)
	}
	if got := c.PrefetchCount(); got != 1 {
		t.Fatalf("expected prefetchCount 1, got %d", got)
	}
}

func TestPrefetchSkipsColdEntries(t *testing.T) {
	c := prefetchTestCache(t)
	res := &fakePrefetchResolver{ttl: 10}
	c.SetPrefetcher(res)

	// 仅命中 1 次，未达门槛 3
	putHotEntry(t, c, "cold.com", 10, 1)

	c.prefetchHotEntries(time.Now())
	if got := res.callCount(); got != 0 {
		t.Fatalf("expected no prefetch for cold entry, got %d", got)
	}
}

func TestPrefetchSkipsEntriesFarFromExpiry(t *testing.T) {
	c := prefetchTestCache(t)
	res := &fakePrefetchResolver{ttl: 3600}
	c.SetPrefetcher(res)

	// TTL=3600s，远超预取窗口
	putHotEntry(t, c, "far.com", 3600, 5)

	c.prefetchHotEntries(time.Now())
	if got := res.callCount(); got != 0 {
		t.Fatalf("expected no prefetch for far-expiry entry, got %d", got)
	}
}

func TestPrefetchSkipsNegativeEntries(t *testing.T) {
	c := prefetchTestCache(t)
	res := &fakePrefetchResolver{ttl: 10}
	c.SetPrefetcher(res)

	req := new(dns.Msg)
	req.SetQuestion("missing.com.", dns.TypeA)
	neg := new(dns.Msg)
	neg.SetRcode(req, dns.RcodeNameError)
	if !c.Put(req, neg) {
		t.Fatalf("expected negative entry cached")
	}
	for i := 0; i < 5; i++ {
		if _, hit, _, _ := c.Get(req); !hit {
			t.Fatalf("expected negative hit")
		}
	}

	c.prefetchHotEntries(time.Now())
	if got := res.callCount(); got != 0 {
		t.Fatalf("expected no prefetch for negative entry, got %d", got)
	}
}

func TestPrefetchDisabledIsNoop(t *testing.T) {
	cfg := DefaultCacheConfig()
	cfg.MinTTLEnabled = false
	cfg.Mode = "follow_dns_ttl"
	cfg.PrefetchEnabled = false
	c := NewDNSCache(cfg)
	defer c.Close()

	res := &fakePrefetchResolver{ttl: 10}
	c.SetPrefetcher(res)
	putHotEntry(t, c, "hot.com", 10, 5)

	c.prefetchHotEntries(time.Now())
	if got := res.callCount(); got != 0 {
		t.Fatalf("expected no prefetch when disabled, got %d", got)
	}
}

func TestPrefetchWithoutResolverIsNoop(t *testing.T) {
	c := prefetchTestCache(t)
	putHotEntry(t, c, "hot.com", 10, 5)
	// 未接线解析器不应 panic
	c.prefetchHotEntries(time.Now())
	if got := c.PrefetchCount(); got != 0 {
		t.Fatalf("expected 0 prefetch count without resolver, got %d", got)
	}
}

func TestPrefetchSharesSingleFlightWithConcurrentClient(t *testing.T) {
	c := prefetchTestCache(t)
	entered := make(chan struct{}, 1)
	release := make(chan struct{})
	res := &fakePrefetchResolver{ttl: 10, entered: entered, release: release}
	c.SetPrefetcher(res)
	req := putHotEntry(t, c, "hot.com", 10, 3)

	done := make(chan struct{})
	go func() {
		c.prefetchHotEntries(time.Now())
		close(done)
	}()

	// 等待预取进入上游回源
	<-entered

	// 同一键的并发客户端请求应共享该次回源（singleflight 去重）
	key := CacheKey(req.Question[0].Name, req.Question[0].Qtype, req.Question[0].Qclass)
	var shared bool
	cliDone := make(chan struct{})
	go func() {
		_, shared, _ = c.SingleFlight(key, func() (*dns.Msg, error) {
			return res.Exchange(context.Background(), req)
		})
		close(cliDone)
	}()

	// 确保客户端已进入等待后再放行上游
	time.Sleep(50 * time.Millisecond)
	close(release)

	<-done
	<-cliDone

	if !shared {
		t.Fatalf("expected concurrent client to share the in-flight prefetch")
	}
	if got := res.callCount(); got != 1 {
		t.Fatalf("expected upstream called exactly once, got %d", got)
	}
}

func TestNormalizeCacheConfigPrefetchBounds(t *testing.T) {
	cfg := CacheConfig{}
	NormalizeCacheConfig(&cfg)
	if cfg.PrefetchThreshold <= 0 || cfg.PrefetchBeforeExpiryMs <= 0 {
		t.Fatalf("expected prefetch defaults applied: %+v", cfg)
	}

	cfg.PrefetchBeforeExpiryMs = 5
	NormalizeCacheConfig(&cfg)
	if cfg.PrefetchBeforeExpiryMs != 1000 {
		t.Fatalf("expected lower bound 1000ms, got %d", cfg.PrefetchBeforeExpiryMs)
	}

	cfg.PrefetchBeforeExpiryMs = maxPrefetchBeforeMs * 10
	NormalizeCacheConfig(&cfg)
	if cfg.PrefetchBeforeExpiryMs != maxPrefetchBeforeMs {
		t.Fatalf("expected upper bound %d, got %d", maxPrefetchBeforeMs, cfg.PrefetchBeforeExpiryMs)
	}
}
