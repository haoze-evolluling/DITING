package core

import (
	"context"
	"net"
	"sync"
	"testing"
	"time"
)

func TestRateLimiter_Disabled(t *testing.T) {
	cfg := DefaultRateLimitConfig()
	cfg.Enabled = false
	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()

	ip := net.ParseIP("192.168.1.100")
	for i := 0; i < 200; i++ {
		if !limiter.Allow(ip) {
			t.Fatalf("expected all requests to be allowed when limiter is disabled")
		}
	}
}

func TestRateLimiter_BurstAndRate(t *testing.T) {
	fakeNow := time.Now()
	cfg := RateLimitConfig{
		Enabled:    true,
		Rate:       10.0, // 10 tokens / sec
		Burst:      5,    // burst 5
		IPv4Prefix: 32,
		IPv6Prefix: 128,
		ExemptIPs:  []string{},
	}

	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()
	limiter.clock = func() time.Time { return fakeNow }

	ip := net.ParseIP("192.168.1.50")

	// 初始 5 个突发请求应当允许
	for i := 0; i < 5; i++ {
		if !limiter.Allow(ip) {
			t.Fatalf("request %d within burst limit should be allowed", i+1)
		}
	}

	// 第 6 个立即发送应当被拒绝
	if limiter.Allow(ip) {
		t.Fatalf("request beyond burst capacity should be rejected")
	}

	// 前进 0.5 秒 (生成 5 个 token)
	fakeNow = fakeNow.Add(500 * time.Millisecond)
	allowedCount := 0
	for i := 0; i < 5; i++ {
		if limiter.Allow(ip) {
			allowedCount++
		}
	}
	if allowedCount == 0 {
		t.Fatalf("expected tokens to refill after 500ms, allowedCount=%d", allowedCount)
	}
}

func TestRateLimiter_ExemptIPs(t *testing.T) {
	cfg := RateLimitConfig{
		Enabled:    true,
		Rate:       1.0,
		Burst:      1,
		IPv4Prefix: 32,
		IPv6Prefix: 128,
		ExemptIPs:  []string{"127.0.0.1", "10.0.0.0/24"},
	}

	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()

	loopback := net.ParseIP("127.0.0.1")
	for i := 0; i < 10; i++ {
		if !limiter.Allow(loopback) {
			t.Fatalf("loopback should be exempt from rate limiting")
		}
	}

	subnetIP := net.ParseIP("10.0.0.42")
	for i := 0; i < 10; i++ {
		if !limiter.Allow(subnetIP) {
			t.Fatalf("CIDR exempt IP should be allowed")
		}
	}
}

func TestRateLimiter_SubnetAggregation(t *testing.T) {
	cfg := RateLimitConfig{
		Enabled:    true,
		Rate:       1.0,
		Burst:      2,
		IPv4Prefix: 24, // 同一 /24 网段共享限流配额
		IPv6Prefix: 128,
		ExemptIPs:  []string{},
	}

	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()

	ip1 := net.ParseIP("192.168.1.10")
	ip2 := net.ParseIP("192.168.1.20")

	if !limiter.Allow(ip1) {
		t.Fatal("first query on /24 should pass")
	}
	if !limiter.Allow(ip2) {
		t.Fatal("second query on /24 should pass")
	}
	// 第三次应当被耗尽
	if limiter.Allow(ip1) {
		t.Fatal("third query on /24 should be rate limited")
	}

	// 另一个 /24 网段应独立
	otherSubnet := net.ParseIP("192.168.2.10")
	if !limiter.Allow(otherSubnet) {
		t.Fatal("query on different /24 should pass")
	}
}

func TestRateLimiter_ConcurrentAccess(t *testing.T) {
	cfg := RateLimitConfig{
		Enabled:    true,
		Rate:       100.0,
		Burst:      50,
		IPv4Prefix: 32,
		IPv6Prefix: 128,
		ExemptIPs:  []string{},
	}

	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			ip := net.ParseIP("192.168.1.1")
			for j := 0; j < 5; j++ {
				_ = limiter.Allow(ip)
			}
		}(i)
	}
	wg.Wait()
}

func TestRateLimiter_ZeroConfigDefaults(t *testing.T) {
	// 验证未传 Rate/Burst 或反序列化为 0 时的默认回退保护
	zeroCfg := RateLimitConfig{
		Enabled: true,
	}
	limiter := NewRateLimiter(context.Background(), zeroCfg)
	defer limiter.Close()

	ip := net.ParseIP("192.168.1.100")
	// 不应因 Rate/Burst 为 0 而直接全部拒绝
	if !limiter.Allow(ip) {
		t.Fatal("zero config should fallback to safe defaults, not block immediately")
	}
}

func TestRateLimiter_CapacityEviction(t *testing.T) {
	cfg := RateLimitConfig{
		Enabled: true,
		Rate:    10.0,
		Burst:   10,
	}
	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()
	limiter.maxBuckets = 3 // 设定测试小容量

	fakeNow := time.Now()
	limiter.clock = func() time.Time { return fakeNow }

	// 创建 3 个客户端桶
	limiter.Allow(net.ParseIP("10.0.0.1"))
	limiter.Allow(net.ParseIP("10.0.0.2"))
	limiter.Allow(net.ParseIP("10.0.0.3"))

	if len(limiter.buckets) != 3 {
		t.Fatalf("expected 3 buckets, got %d", len(limiter.buckets))
	}

	// 推进 65 秒使旧桶空闲
	fakeNow = fakeNow.Add(65 * time.Second)

	// 新客户端访问，应触发内联淘汰并成功允许
	if !limiter.Allow(net.ParseIP("10.0.0.4")) {
		t.Fatal("new client should be allowed after evicting idle buckets")
	}
}

func TestRateLimiter_UpdateConfig(t *testing.T) {
	cfg := RateLimitConfig{
		Enabled: true,
		Rate:    1.0,
		Burst:   1,
	}
	limiter := NewRateLimiter(context.Background(), cfg)
	defer limiter.Close()

	ip := net.ParseIP("192.168.1.200")
	if !limiter.Allow(ip) {
		t.Fatal("first query should pass")
	}
	if limiter.Allow(ip) {
		t.Fatal("second query should be rate limited")
	}

	// 动态更新提升 burst 为 10
	limiter.UpdateConfig(RateLimitConfig{
		Enabled: true,
		Rate:    10.0,
		Burst:   10,
	})

	// 更新后应立即扩容并允许
	if !limiter.Allow(ip) {
		t.Fatal("query should pass after updating burst capacity")
	}
}

