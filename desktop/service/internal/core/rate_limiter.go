package core

// rate_limiter.go keeps the public shape of the client rate limiter: the config types, the janitor
// goroutine and the `IsEnabled` fast path the DNS middleware reads. The decision itself — token
// bucket, configuration normalisation, exemption parsing, prefix aggregation and capacity eviction —
// is in rust/diting-ratelimit-core (see ratelimit_native.go).
//
// The split is the one the other desktop kernels use: Go passes the clock (`now_ns`) and keeps the
// goroutine plumbing; the state and the arithmetic live in Rust, with no second implementation to
// drift.

import (
	"context"
	"net"
	"sync"
	"sync/atomic"
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

// defaultRateLimitMaxBuckets 是内核的容量上限。它曾是一个 Go 字段，测试会直接调小，
// 所以每次 Allow 都把它随参数交给内核，而不是在内核里写死。
const defaultRateLimitMaxBuckets = 16384

// RateLimiter 客户端限流保护引擎，线程安全。
//
// kernelMu 只保护内核句柄本身：Allow 走读锁，Close 走写锁并在其中释放句柄，
// 所以关闭过程中不会有调用踩到已释放的内存。
type RateLimiter struct {
	kernelMu sync.RWMutex
	kernel   *rateLimitNativeLimiter
	enabled  atomic.Bool

	// maxBuckets 只由测试与诊断使用，随每次 Allow 传给内核。
	maxBuckets int
	// clock 可注入，测试据此驱动令牌补充而不用 sleep。
	clock func() time.Time

	// janitorMu / janitorCtx / janitorCancel 管理闲置桶回收协程的生命周期。
	// 它的启停跟随 cfg.Enabled 热更新，而不是只在构造期判定一次。
	janitorMu     sync.Mutex
	janitorCtx    context.Context
	janitorCancel context.CancelFunc
	stopCh        chan struct{}
}

// NewRateLimiter 创建客户端限流引擎。
//
// 内核缺失时返回错误：让服务启动失败，好过让用户以为限流已开启而实际全部放行。
func NewRateLimiter(ctx context.Context, cfg RateLimitConfig) (*RateLimiter, error) {
	kernel, err := buildRateLimitNativeLimiter(cfg)
	if err != nil {
		return nil, err
	}
	r := &RateLimiter{
		kernel:     kernel,
		maxBuckets: defaultRateLimitMaxBuckets,
		clock:      time.Now,
		janitorCtx: ctx,
		stopCh:     make(chan struct{}),
	}
	r.enabled.Store(cfg.Enabled)
	r.syncJanitorLocked(cfg.Enabled)
	return r, nil
}

// UpdateConfig 动态更新限流运行配置。
//
// 桶与存量令牌都保留：内核按新的 burst 上调容量或把令牌钳到新上限，
// 与迁移前逐桶调整的语义一致。配置被内核拒绝时返回错误，调用方不应持久化新配置。
func (r *RateLimiter) UpdateConfig(cfg RateLimitConfig) error {
	if r == nil {
		return nil
	}
	r.kernelMu.RLock()
	err := r.kernel.configure(cfg)
	r.kernelMu.RUnlock()
	if err != nil {
		return err
	}

	r.enabled.Store(cfg.Enabled)
	r.janitorMu.Lock()
	r.syncJanitorLocked(cfg.Enabled)
	r.janitorMu.Unlock()
	return nil
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

// IsEnabled 获取当前限流是否开启
func (r *RateLimiter) IsEnabled() bool {
	return r != nil && r.enabled.Load()
}

// Allow 判断来自该客户端 IP 的单次请求是否允许通过。
//
// nil 地址与未启用限流都在 Go 侧直接放行（与迁移前同一顺序），其余判定交给内核：
// 豁免、按前缀聚合成桶、补充令牌、容量淘汰。
func (r *RateLimiter) Allow(ip net.IP) bool {
	if r == nil || !r.enabled.Load() {
		return true
	}
	if ip == nil {
		return true
	}
	r.kernelMu.RLock()
	allowed := r.kernel.allow(ip, r.nowNanos(), r.maxBuckets)
	r.kernelMu.RUnlock()
	return allowed
}

// cleanupIdleBuckets 是回收协程每分钟一次的调用。
//
// 内核里 isIdle 的条件是「令牌满且一分钟未写入」，而一次 allow 之后令牌必然差一个，
// 所以这条路径实际上不会删掉任何桶——迁移前就是这样，语料把结论固化了。
func (r *RateLimiter) cleanupIdleBuckets() {
	if r == nil {
		return
	}
	now := r.nowNanos()
	r.kernelMu.RLock()
	r.kernel.cleanup(now)
	r.kernelMu.RUnlock()
}

// bucketCount 返回当前桶数量，供测试与诊断使用。
func (r *RateLimiter) bucketCount() int {
	if r == nil {
		return 0
	}
	r.kernelMu.RLock()
	defer r.kernelMu.RUnlock()
	info, err := r.kernel.info()
	if err != nil {
		return 0
	}
	return int(info.Buckets)
}

func (r *RateLimiter) nowNanos() int64 {
	clock := r.clock
	if clock == nil {
		clock = time.Now
	}
	return clock().UnixNano()
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

// Close 停止后台清理协程并释放内核句柄。
func (r *RateLimiter) Close() {
	if r == nil {
		return
	}
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

	r.kernelMu.Lock()
	r.kernel.free()
	r.kernelMu.Unlock()
}
