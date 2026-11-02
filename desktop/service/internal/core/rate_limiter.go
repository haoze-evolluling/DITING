package core

import (
	"context"
	"net"
	"strings"
	"sync"
	"time"
)

// RateLimitConfig 客户端请求速率限制配置。
// 借鉴自 blocky (rate_limiting_resolver.go) 与 Pi-hole / AdGuard Home，
// 提供基于令牌桶算法的抗 DoS 与抗 DNS 放大攻击保护。
type RateLimitConfig struct {
	Enabled    bool     `json:"enabled"`    // 是否启用限流保护
	Rate       float64  `json:"rate"`       // 每秒生成令牌速率（默认 50 令牌/秒）
	Burst      int      `json:"burst"`      // 令牌桶突发容量上限（默认 100）
	IPv4Prefix int      `json:"ipv4Prefix"` // IPv4 客户端聚合掩码长度（默认 32，即按独立 IP 统计；局域网可配 24）
	IPv6Prefix int      `json:"ipv6Prefix"` // IPv6 客户端聚合掩码长度（默认 128，局域网可配 56 或 64）
	ExemptIPs  []string `json:"exemptIPs"`  // 豁免限流的白名单 IP 或 CIDR 网段（如本地回环 127.0.0.1、::1）
}

// DefaultRateLimitConfig 返回默认客户端限流配置
func DefaultRateLimitConfig() RateLimitConfig {
	return RateLimitConfig{
		Enabled:    false,
		Rate:       50.0,
		Burst:      100,
		IPv4Prefix: 32,
		IPv6Prefix: 128,
		ExemptIPs:  []string{"127.0.0.1", "::1"},
	}
}

type clientBucket struct {
	mu         sync.Mutex
	rate       float64
	burst      float64
	tokens     float64
	lastRefill time.Time
}

func (b *clientBucket) allow(now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	elapsed := now.Sub(b.lastRefill).Seconds()
	b.lastRefill = now
	b.tokens += elapsed * b.rate
	if b.tokens > b.burst {
		b.tokens = b.burst
	}

	if b.tokens >= 1.0 {
		b.tokens -= 1.0
		return true
	}
	return false
}

func (b *clientBucket) isIdle(now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.tokens >= b.burst && now.Sub(b.lastRefill) > 60*time.Second
}

// RateLimiter 客户端限流保护引擎，线程安全
type RateLimiter struct {
	mu         sync.RWMutex
	cfg        RateLimitConfig
	buckets    map[string]*clientBucket
	exemptIPs  map[string]struct{}
	exemptNets []*net.IPNet
	maxBuckets int
	stopCh     chan struct{}
	clock      func() time.Time

	// janitorCtx / janitorCancel 管理闲置桶回收协程的生命周期。
	// 它的启停跟随 cfg.Enabled 热更新，而不是只在构造期判定一次。
	janitorMu     sync.Mutex
	janitorCtx    context.Context
	janitorCancel context.CancelFunc
}

// NewRateLimiter 创建客户端限流引擎
func NewRateLimiter(ctx context.Context, cfg RateLimitConfig) *RateLimiter {
	if cfg.Rate <= 0 {
		cfg.Rate = 50.0
	}
	if cfg.Burst <= 0 {
		cfg.Burst = 100
	}
	if cfg.IPv4Prefix <= 0 || cfg.IPv4Prefix > 32 {
		cfg.IPv4Prefix = 32
	}
	if cfg.IPv6Prefix <= 0 || cfg.IPv6Prefix > 128 {
		cfg.IPv6Prefix = 128
	}

	r := &RateLimiter{
		cfg:        cfg,
		buckets:    make(map[string]*clientBucket),
		exemptIPs:  make(map[string]struct{}),
		maxBuckets: 16384,
		stopCh:     make(chan struct{}),
		clock:      time.Now,
	}
	r.parseExemptions(cfg.ExemptIPs)
	r.janitorCtx = ctx
	r.syncJanitorLocked(cfg.Enabled)

	return r
}

// syncJanitorLocked 按启用状态启停闲置桶回收协程。调用方须持有 janitorMu。
func (r *RateLimiter) syncJanitorLocked(enabled bool) {
	if enabled {
		if r.janitorCancel != nil {
			return // 已在运行
		}
		ctx := r.janitorCtx
		if ctx == nil {
			ctx = context.Background()
		}
		janitorCtx, cancel := context.WithCancel(ctx)
		r.janitorCancel = cancel
		go r.runJanitor(janitorCtx, time.Minute)
		return
	}
	if r.janitorCancel != nil {
		r.janitorCancel()
		r.janitorCancel = nil
	}
}

// UpdateConfig 动态更新限流运行配置
func (r *RateLimiter) UpdateConfig(cfg RateLimitConfig) {
	if cfg.Rate <= 0 {
		cfg.Rate = 50.0
	}
	if cfg.Burst <= 0 {
		cfg.Burst = 100
	}
	if cfg.IPv4Prefix <= 0 || cfg.IPv4Prefix > 32 {
		cfg.IPv4Prefix = 32
	}
	if cfg.IPv6Prefix <= 0 || cfg.IPv6Prefix > 128 {
		cfg.IPv6Prefix = 128
	}

	// 回收协程的启停与配置更新同步：运行中把限流从关闭改为开启，
	// 若不同时启动 janitor，历史桶就只能等 16384 上限的内联淘汰兜底。
	r.janitorMu.Lock()
	r.syncJanitorLocked(cfg.Enabled)
	r.janitorMu.Unlock()

	r.mu.Lock()
	defer r.mu.Unlock()
	r.cfg = cfg
	r.exemptIPs = make(map[string]struct{})
	r.exemptNets = nil
	r.parseExemptions(cfg.ExemptIPs)

	for _, b := range r.buckets {
		b.mu.Lock()
		oldBurst := b.burst
		b.rate = cfg.Rate
		b.burst = float64(cfg.Burst)
		if b.burst > oldBurst {
			b.tokens += (b.burst - oldBurst)
		}
		if b.tokens > b.burst {
			b.tokens = b.burst
		}
		b.mu.Unlock()
	}
}

func (r *RateLimiter) parseExemptions(entries []string) {
	for _, entry := range entries {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		if strings.Contains(entry, "/") {
			if _, ipNet, err := net.ParseCIDR(entry); err == nil {
				r.exemptNets = append(r.exemptNets, ipNet)
			}
		} else {
			if ip := net.ParseIP(entry); ip != nil {
				if v4 := ip.To4(); v4 != nil {
					ip = v4
				}
				r.exemptIPs[ip.String()] = struct{}{}
			}
		}
	}
}

// IsEnabled 获取当前限流是否开启
func (r *RateLimiter) IsEnabled() bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.cfg.Enabled
}

// IsExempt 判断客户端 IP 是否被豁免限流
func (r *RateLimiter) IsExempt(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	if _, ok := r.exemptIPs[ip.String()]; ok {
		return true
	}
	for _, ipNet := range r.exemptNets {
		if ipNet.Contains(ip) {
			return true
		}
	}
	return false
}

// Allow 判断来自该客户端 IP 的单次请求是否允许通过
func (r *RateLimiter) Allow(ip net.IP) bool {
	if !r.IsEnabled() {
		return true
	}
	if ip == nil || r.IsExempt(ip) {
		return true
	}

	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}

	key := r.bucketKey(ip)
	now := r.clock()

	r.mu.Lock()
	bucket, ok := r.buckets[key]
	if !ok {
		if len(r.buckets) >= r.maxBuckets {
			// 容量达上限时，先内联淘汰空闲桶，避免无状态新客户端直接饿死
			for k, b := range r.buckets {
				if b.isIdle(now) {
					delete(r.buckets, k)
				}
			}
			// 若仍然超限，淘汰最久未活跃的桶腾出空间
			if len(r.buckets) >= r.maxBuckets {
				var oldestKey string
				var oldestTime time.Time
				for k, b := range r.buckets {
					b.mu.Lock()
					refill := b.lastRefill
					b.mu.Unlock()
					if oldestKey == "" || refill.Before(oldestTime) {
						oldestKey = k
						oldestTime = refill
					}
				}
				if oldestKey != "" {
					delete(r.buckets, oldestKey)
				}
			}
		}
		bucket = &clientBucket{
			rate:       r.cfg.Rate,
			burst:      float64(r.cfg.Burst),
			tokens:     float64(r.cfg.Burst),
			lastRefill: now,
		}
		r.buckets[key] = bucket
	}
	r.mu.Unlock()

	return bucket.allow(now)
}

func (r *RateLimiter) bucketKey(ip net.IP) string {
	r.mu.RLock()
	v4Prefix := r.cfg.IPv4Prefix
	v6Prefix := r.cfg.IPv6Prefix
	r.mu.RUnlock()

	if v4 := ip.To4(); v4 != nil {
		if v4Prefix <= 0 || v4Prefix > 32 {
			v4Prefix = 32
		}
		return v4.Mask(net.CIDRMask(v4Prefix, 32)).String()
	}
	if v6Prefix <= 0 || v6Prefix > 128 {
		v6Prefix = 128
	}
	return ip.To16().Mask(net.CIDRMask(v6Prefix, 128)).String()
}

func (r *RateLimiter) runJanitor(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-r.stopCh:
			return
		case <-ticker.C:
			r.cleanupIdleBuckets()
		}
	}
}

func (r *RateLimiter) cleanupIdleBuckets() {
	now := r.clock()
	r.mu.Lock()
	defer r.mu.Unlock()

	for key, b := range r.buckets {
		if b.isIdle(now) {
			delete(r.buckets, key)
		}
	}
}

// Close 停止后台清理协程
func (r *RateLimiter) Close() {
	r.janitorMu.Lock()
	if r.janitorCancel != nil {
		r.janitorCancel()
		r.janitorCancel = nil
	}
	r.janitorMu.Unlock()
	select {
	case <-r.stopCh:
	default:
		close(r.stopCh)
	}
}
