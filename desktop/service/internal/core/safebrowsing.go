package core

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// 哈希前缀查询的固定参数，与 AdGuard 的服务端约定一致。
const (
	// SafeBrowsingSuffix 恶意网址库的 TXT 查询后缀
	SafeBrowsingSuffix = "sb.dns.adguard.com."
	// ParentalControlSuffix 家长控制的 TXT 查询后缀
	ParentalControlSuffix = "pc.dns.adguard.com."

	// ReasonSafeBrowsing 查询日志中的命中原由
	ReasonSafeBrowsing = "SAFE_BROWSING"
	// ReasonParentalControl 查询日志中的命中原由
	ReasonParentalControl = "PARENTAL_CONTROL"
)

// 声誉查询的默认参数
const (
	DefaultSafeBrowsingTimeoutMs = 3000
	DefaultSafeBrowsingCacheSize = 10000
	DefaultSafeBrowsingCacheTTL  = 600 // 秒
)

// SafeBrowsingConfig 恶意网址库与家长控制配置
type SafeBrowsingConfig struct {
	// Enabled 恶意网址库（Safe Browsing）
	Enabled bool `json:"enabled"`
	// ParentalEnabled 家长控制（色情/暴力等成人内容分类）
	ParentalEnabled bool `json:"parentalEnabled"`
	// TimeoutMs 单次哈希前缀查询的超时（毫秒）
	TimeoutMs int `json:"timeoutMs"`
	// CacheSize 哈希前缀缓存条目数上限
	CacheSize int `json:"cacheSize"`
	// CacheTTLSeconds 缓存有效期（秒）
	CacheTTLSeconds int `json:"cacheTTLSeconds"`
}

// DefaultSafeBrowsingConfig 返回默认配置（默认全部关闭）
//
// 关闭是刻意的：开启后每一次新域名的解析都会附带一次发往第三方的
// 哈希前缀查询，是否接受这一隐私代价应当由用户自己决定。
func DefaultSafeBrowsingConfig() SafeBrowsingConfig {
	return SafeBrowsingConfig{
		Enabled:         false,
		ParentalEnabled: false,
		TimeoutMs:       DefaultSafeBrowsingTimeoutMs,
		CacheSize:       DefaultSafeBrowsingCacheSize,
		CacheTTLSeconds: DefaultSafeBrowsingCacheTTL,
	}
}

// NormalizeSafeBrowsingConfig 校验与修补配置默认值
func NormalizeSafeBrowsingConfig(cfg *SafeBrowsingConfig) {
	if cfg == nil {
		return
	}
	if cfg.TimeoutMs < 100 || cfg.TimeoutMs > 30000 {
		cfg.TimeoutMs = DefaultSafeBrowsingTimeoutMs
	}
	if cfg.CacheSize < 0 {
		cfg.CacheSize = 0
	}
	if cfg.CacheTTLSeconds <= 0 {
		cfg.CacheTTLSeconds = DefaultSafeBrowsingCacheTTL
	}
}

// SafeBrowsingVerdict 一次声誉查询的结论。
//
// Blocked 与 Failed 必须分开看：前者是「查到了，确实该拦」，
// 后者是「没查到，因为根本问不到」。把失败当成命中会让上游一抖动
// 就整网断解析；当成未命中又会让攻击者靠制造失败来绕过。
// 本项目的取舍是失败即放行（fail-open），并如实记录。
type SafeBrowsingVerdict struct {
	Blocked bool
	Service string
	Failed  bool
	Err     error
}

// SafeBrowsingStats 声誉查询的累计统计
type SafeBrowsingStats struct {
	CacheHits   int64 `json:"cacheHits"`
	CacheMisses int64 `json:"cacheMisses"`
	Lookups     int64 `json:"lookups"`
	Failures    int64 `json:"failures"`
	Blocked     int64 `json:"blocked"`
}

// SafeBrowsingEngine 恶意网址库与家长控制引擎。
//
// 机制与 AdGuard Home 的 hashprefix 插件相同：把域名及其各级父域做
// SHA-256，取前 2 字节的十六进制拼成查询名发往第三方权威服务器，
// 对方返回命中的完整摘要；本地再与请求过的摘要逐一比对。
// 传输过程中第三方只看到 2 字节前缀，无法还原完整域名。
//
// 归一化、摘要、查询名、TXT 解析与缓存都在 Rust 内核里
// （rust/diting-safebrowsing-core）；这里保留上游查询、超时、
// fail-open 取舍与计数，因为它们要么要 dns.Msg，要么就是日志与统计。
type SafeBrowsingEngine struct {
	mu       sync.RWMutex
	enabled  bool
	parental bool
	timeout  time.Duration
	resolver Resolver
	kernel   *sbNativeHandle

	statsMu    sync.Mutex
	cacheHits  int64
	cacheMiss  int64
	lookups    int64
	failures   int64
	blockedCnt int64
}

// sbService 一个服务在内核里的编号与日志里的名字
type sbService struct {
	id   uint8
	name string
}

var (
	sbServiceMalware  = sbService{id: sbServiceIDMalware, name: ReasonSafeBrowsing}
	sbServiceParental = sbService{id: sbServiceIDParental, name: ReasonParentalControl}
)

// NewSafeBrowsingEngine 创建声誉查询引擎
//
// resolver 用于发出哈希前缀查询；为 nil 时引擎始终返回失败（即放行），
// 这样在上游尚未装配完成的启动阶段不会误拦。
//
// 内核缺失、ABI 不匹配或建不出句柄都是硬错误：宁可让服务启动失败，
// 也不能让「界面显示已开启、实际什么都没查」这种状态跑起来。
func NewSafeBrowsingEngine(cfg SafeBrowsingConfig, resolver Resolver) (*SafeBrowsingEngine, error) {
	NormalizeSafeBrowsingConfig(&cfg)

	kernel, err := newSBNativeHandle(cfg.CacheSize, cfg.CacheTTLSeconds)
	if err != nil {
		return nil, fmt.Errorf("加载声誉查询内核失败: %w", err)
	}

	return &SafeBrowsingEngine{
		enabled:  cfg.Enabled,
		parental: cfg.ParentalEnabled,
		timeout:  time.Duration(cfg.TimeoutMs) * time.Millisecond,
		resolver: resolver,
		kernel:   kernel,
	}, nil
}

// IsEnabled 检查是否有任一服务处于启用状态
func (e *SafeBrowsingEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.enabled || e.parental
}

// Configure 更新配置
//
// 缓存容量与有效期变化时由内核整体重建缓存：存量条目按旧规则写入，
// 沿用它们会让新旧 TTL 混在一起，不如清空后重新收敛。
func (e *SafeBrowsingEngine) Configure(cfg SafeBrowsingConfig) {
	NormalizeSafeBrowsingConfig(&cfg)

	e.mu.Lock()
	defer e.mu.Unlock()

	e.kernel.configure(cfg.CacheSize, cfg.CacheTTLSeconds)
	e.enabled = cfg.Enabled
	e.parental = cfg.ParentalEnabled
	e.timeout = time.Duration(cfg.TimeoutMs) * time.Millisecond
}

// SetResolver 装配上游解析器（启动顺序上解析器可能晚于本引擎就绪）
func (e *SafeBrowsingEngine) SetResolver(resolver Resolver) {
	e.mu.Lock()
	e.resolver = resolver
	e.mu.Unlock()
}

// Stats 返回累计统计
func (e *SafeBrowsingEngine) Stats() SafeBrowsingStats {
	e.statsMu.Lock()
	defer e.statsMu.Unlock()
	return SafeBrowsingStats{
		CacheHits:   e.cacheHits,
		CacheMisses: e.cacheMiss,
		Lookups:     e.lookups,
		Failures:    e.failures,
		Blocked:     e.blockedCnt,
	}
}

// Check 查询该域名是否被任一启用的服务标记。
//
// 先查恶意网址库再查家长控制：两者命中都会拦截，但前者更严重，
// 日志里优先归因于它更有诊断价值。
func (e *SafeBrowsingEngine) Check(ctx context.Context, host string) SafeBrowsingVerdict {
	e.mu.RLock()
	sbOn := e.enabled
	pcOn := e.parental
	timeout := e.timeout
	resolver := e.resolver
	kernel := e.kernel
	e.mu.RUnlock()

	if !sbOn && !pcOn {
		return SafeBrowsingVerdict{}
	}

	// 第一次调用先做归一化与校验：非法主机名不产生任何结论，
	// 也不该被当成「解析器未就绪」的失败。
	first := sbServiceMalware
	if !sbOn {
		first = sbServiceParental
	}
	plan, ok := kernel.plan(first.id, host)
	if !ok {
		return SafeBrowsingVerdict{}
	}
	if resolver == nil {
		e.recordFailure()
		return SafeBrowsingVerdict{Failed: true, Err: fmt.Errorf("上游解析器尚未就绪")}
	}
	// 主机本身就是公共后缀（没有任何可核对的摘要）时同样不产生结论
	if plan.empty {
		return SafeBrowsingVerdict{}
	}

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	if sbOn {
		if v := e.checkPlanned(ctx, kernel, resolver, sbServiceMalware, plan); v.Blocked || v.Failed {
			return v
		}
	}
	if !pcOn {
		return SafeBrowsingVerdict{}
	}
	if sbOn {
		// 恶意网址库未命中时再走家长控制，缓存查询在那一刻做，
		// 与旧实现「命中即短路」的走法保持一致。
		pcPlan, ok := kernel.plan(sbServiceParental.id, host)
		if !ok {
			return SafeBrowsingVerdict{}
		}
		plan = pcPlan
	}
	return e.checkPlanned(ctx, kernel, resolver, sbServiceParental, plan)
}

// checkPlanned 用单个服务核对一份已算好的计划
func (e *SafeBrowsingEngine) checkPlanned(ctx context.Context, kernel *sbNativeHandle, resolver Resolver,
	service sbService, plan sbPlan) SafeBrowsingVerdict {
	if plan.found {
		e.record(true, plan.blocked)
		if plan.blocked {
			return SafeBrowsingVerdict{Blocked: true, Service: service.name}
		}
		return SafeBrowsingVerdict{}
	}

	resp, err := resolver.Exchange(ctx, buildHashQuestion(plan.question))
	if err != nil {
		e.recordFailure()
		return SafeBrowsingVerdict{Failed: true, Err: err}
	}

	blocked := kernel.apply(service.id, plan.hashes, txtChunks(resp))
	e.record(false, blocked)
	if blocked {
		return SafeBrowsingVerdict{Blocked: true, Service: service.name}
	}
	return SafeBrowsingVerdict{}
}

// record 记账一次结论；fromCache 与 blocked 分开传，是因为
// 「命中缓存」与「判定为拦截」是两件互不蕴含的事。
func (e *SafeBrowsingEngine) record(fromCache, blocked bool) {
	e.statsMu.Lock()
	if fromCache {
		e.cacheHits++
	} else {
		e.cacheMiss++
	}
	e.lookups++
	if blocked {
		e.blockedCnt++
	}
	e.statsMu.Unlock()
}

func (e *SafeBrowsingEngine) recordFailure() {
	e.statsMu.Lock()
	e.failures++
	e.statsMu.Unlock()
}

// buildHashQuestion 把内核给出的查询名包成一条 TXT 查询
func buildHashQuestion(name string) *dns.Msg {
	req := new(dns.Msg)
	req.SetQuestion(name, dns.TypeTXT)
	req.RecursionDesired = true
	return req
}

// txtChunks 取出应答里所有 TXT 记录的文本段
//
// 段长与十六进制格式的校验在内核里：长度或内容不符的条目直接忽略，
// 那是服务端的多余输出或格式变更，当成摘要参与比对只会制造莫名其妙的拦截。
func txtChunks(resp *dns.Msg) []string {
	if resp == nil {
		return nil
	}
	var out []string
	for _, rr := range resp.Answer {
		txt, ok := rr.(*dns.TXT)
		if !ok {
			continue
		}
		out = append(out, txt.Txt...)
	}
	return out
}
