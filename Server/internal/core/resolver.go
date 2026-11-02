package core

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// DNSProtocol 定义支持的上游传输协议类型
type DNSProtocol string

const (
	ProtocolPlain DNSProtocol = "PLAIN"
	ProtocolDoH   DNSProtocol = "DOH"
	ProtocolDoT   DNSProtocol = "DOT"
	ProtocolDoQ   DNSProtocol = "DOQ"
	ProtocolDoH3  DNSProtocol = "DOH3"
)

// IsEncrypted 判断该协议是否为加密传输。
//
// 加密传输才适用 RFC 7830 的 EDNS0 填充（长度指纹抹平）；
// 明文 UDP/TCP 填充无隐私收益，只会徒增报文体积。
func (p DNSProtocol) IsEncrypted() bool {
	switch p {
	case ProtocolDoH, ProtocolDoT, ProtocolDoQ, ProtocolDoH3:
		return true
	default:
		return false
	}
}

// IsValidProtocol 校验上游传输协议字符串是否受支持
func IsValidProtocol(s string) bool {
	switch strings.ToUpper(strings.TrimSpace(s)) {
	case "PLAIN", "UDP", "TCP", "DOH", "HTTPS", "DOT", "TLS", "DOQ", "QUIC", "DOH3", "H3", "":
		return true
	default:
		return false
	}
}

// ParseProtocol 解析协议字符串
func ParseProtocol(s string) DNSProtocol {
	switch strings.ToUpper(strings.TrimSpace(s)) {
	case "DOH", "HTTPS":
		return ProtocolDoH
	case "DOH3", "H3":
		return ProtocolDoH3
	case "DOT", "TLS":
		return ProtocolDoT
	case "DOQ", "QUIC":
		return ProtocolDoQ
	default:
		return ProtocolPlain
	}
}

// IsHTTPStyleProtocol 判断该协议是否以 HTTPS 语义承载（需要 URL 而非裸地址）
func (p DNSProtocol) IsHTTPStyleProtocol() bool {
	return p == ProtocolDoH || p == ProtocolDoH3
}

// ProviderConfig 上游提供者配置结构
type ProviderConfig struct {
	ID       string      `json:"id"`
	Protocol DNSProtocol `json:"protocol"`
	Server   string      `json:"server"` // host:port 格式，也可直接填写 sdns:// 印章
	URL      string      `json:"url"`    // DoH/DoH3 URL 地址
	Weight   int         `json:"weight,omitempty"`
	// Pin 为十六进制证书指纹（SHA-256(RawTBSCertificate)）。
	//
	// 安全提示：固定指纹会**替代**系统 CA 链校验，仅应用于自签或私有 CA
	// 部署的上游；留空即沿用标准校验，为默认且推荐的状态。
	Pin string `json:"pin,omitempty"`
}

// ResolverConfig 上游解析器整体配置
type ResolverConfig struct {
	Mode              string            `json:"mode"`
	Providers         []ProviderConfig  `json:"providers"`
	Bootstrap         BootstrapConfig   `json:"bootstrap"`
	ConditionalRoutes map[string]string `json:"conditionalRoutes,omitempty"` // 域名后缀分流: domainSuffix -> upstream
	EDNSPadding       int               `json:"ednsPadding,omitempty"`       // RFC 7830 EDNS0 填充块大小（0 为禁用，推荐 128）
	// FallbackProviders 为独立回退链；为空即不启用，主链路行为与未配置时完全一致。
	//
	// 启用后主链路获得一个独立超时（见 FallbackTimeoutMs），
	// 避免慢上游把整条链路的预算吃光导致回退链根本没有机会执行。
	FallbackProviders []ProviderConfig `json:"fallbackProviders,omitempty"`
	// FallbackTimeoutMs 为主链路独立超时（毫秒）。
	// <=0 表示使用 DefaultFallbackTimeoutMs；仅在有回退上游时生效。
	FallbackTimeoutMs int `json:"fallbackTimeoutMs,omitempty"`
	// FallbackOnRcode 指定触发回退的响应码。
	//
	// 不加 omitempty：nil（未表态，采用默认）与空切片（明确取消所有响应码触发）
	// 语义不同，序列化时必须保留这一区别，否则界面上取消全部勾选后会被读回默认值。
	FallbackOnRcode []int `json:"fallbackOnRcode"`
	// FallbackOnError 控制传输层故障（超时/连接失败）是否触发回退，默认 true。
	FallbackOnError *bool `json:"fallbackOnError,omitempty"`
}

// Resolver 核心上游解析器接口
type Resolver interface {
	Resolve(ctx context.Context, rawQuery []byte) ([]byte, error)
	Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error)
	Configure(cfg ResolverConfig) error
	Shutdown() error
}

// CoreResolver 纯 Go DNS 核心内核实现
type CoreResolver struct {
	mu          sync.RWMutex
	mode        string
	providers   []*ConfiguredProvider
	bootstrap   *BootstrapResolver
	plain       *PlainResolver
	doh         *DoHResolver
	doh3        *DoH3Resolver
	dot         *DoTResolver
	doq         *DoQResolver
	scheduler   *Scheduler
	router      *ConditionalRouter
	ednsPadding int
	// pinLookup 为按主机名分派的证书固定表，nil 表示未配置任何固定
	pinLookup PinLookup
	// fallbackProviders 为独立回退链；为空表示未启用
	fallbackProviders []*ConfiguredProvider
	// fallbackTimeout 为主链路独立超时；仅在有回退链时生效
	fallbackTimeout time.Duration
	// fallbackOnRcode 为触发回退的响应码集合（已归一化为非空）
	fallbackOnRcode []int
	// fallbackOnError 为传输层故障是否触发回退
	fallbackOnError bool
	// groupUpstreams 为客户端分组 → 专属上游节点的映射；为空表示未启用
	groupUpstreams map[string][]*ConfiguredProvider
	// groupUpstreamIDs 为其持久化形态（仅存 ID），供状态展示与配置回写
	groupUpstreamIDs map[string][]string
}

// NewResolver 创建并初始化核心 DNS 解析器
func NewResolver(cfg ResolverConfig) (*CoreResolver, error) {
	bs := NewBootstrapResolver(cfg.Bootstrap)
	plain := NewPlainResolver(bs)
	doh := NewDoHResolver(bs)
	doh3 := NewDoH3Resolver(bs)
	dot := NewDoTResolver(bs)
	doq := NewDoQResolver(bs)

	r := &CoreResolver{
		bootstrap: bs,
		plain:     plain,
		doh:       doh,
		doh3:      doh3,
		dot:       dot,
		doq:       doq,
		router:    NewConditionalRouter(nil),
	}

	r.scheduler = NewScheduler(r.executeProvider)
	if err := r.Configure(cfg); err != nil {
		return nil, err
	}
	return r, nil
}

// Configure 动态热重载上游与调度配置
func (r *CoreResolver) Configure(cfg ResolverConfig) error {
	if len(cfg.Providers) == 0 {
		return fmt.Errorf("at least one upstream provider is required")
	}

	if err := ValidateBootstrapConfig(cfg.Bootstrap); err != nil {
		return fmt.Errorf("invalid bootstrap configuration: %w", err)
	}

	mode := CanonicalMode(cfg.Mode)

	// 捕获已有节点的统计指标，使动态更新配置时平滑保留健康与延迟历史
	r.mu.RLock()
	oldStats := make(map[string]*ProviderStats, len(r.providers)+len(r.fallbackProviders))
	for _, oldP := range r.providers {
		if oldP != nil && oldP.ID != "" && oldP.Stats != nil {
			oldStats[oldP.ID] = oldP.Stats
		}
	}
	for _, oldP := range r.fallbackProviders {
		if oldP != nil && oldP.ID != "" && oldP.Stats != nil {
			if _, exists := oldStats[oldP.ID]; !exists {
				oldStats[oldP.ID] = oldP.Stats
			}
		}
	}
	r.mu.RUnlock()

	providers, err := buildProviderSet(cfg.Providers, oldStats)
	if err != nil {
		return err
	}

	fallbackProviders, err := buildProviderSet(cfg.FallbackProviders, oldStats)
	if err != nil {
		return fmt.Errorf("fallback chain: %w", err)
	}

	// 证书固定按主机名分派：指纹是 per-provider 的，一份全局 TLS 配置装不下。
	// 回退链上的固定同样必须生效，故一并纳入分派表。
	pinsFor := make([]*ConfiguredProvider, 0, len(providers)+len(fallbackProviders))
	pinsFor = append(pinsFor, providers...)
	pinsFor = append(pinsFor, fallbackProviders...)
	pinLookup := buildPinLookup(pinsFor)

	r.mu.Lock()
	defer r.mu.Unlock()

	r.mode = mode
	r.providers = providers
	// 上游列表被整体替换后，分组专属上游的节点指针也必须重新绑定到新对象上；
	// 否则热更新会让分组仍指向已废弃的旧节点（其统计与连接池都已不再被调度）
	_ = r.applyGroupUpstreamsLocked(r.groupUpstreamIDs)
	r.fallbackProviders = fallbackProviders
	r.fallbackTimeout = fallbackTimeoutOf(cfg.FallbackTimeoutMs)
	r.fallbackOnRcode = fallbackRcodes(cfg.FallbackOnRcode)
	r.fallbackOnError = true
	if cfg.FallbackOnError != nil {
		r.fallbackOnError = *cfg.FallbackOnError
	}
	r.ednsPadding = cfg.EDNSPadding
	if r.ednsPadding < 0 {
		r.ednsPadding = 0
	}
	if r.bootstrap != nil {
		r.bootstrap.UpdateConfig(cfg.Bootstrap)
		if r.doh != nil {
			r.doh.SetBootstrap(r.bootstrap)
		}
		if r.doh3 != nil {
			r.doh3.SetBootstrap(r.bootstrap)
		}
		if r.dot != nil {
			r.dot.SetBootstrap(r.bootstrap)
		}
		if r.doq != nil {
			r.doq.SetBootstrap(r.bootstrap)
		}
		if r.plain != nil {
			r.plain.SetBootstrap(r.bootstrap)
		}
	}

	r.pinLookup = pinLookup

	if r.doh != nil {
		r.doh.SetPinLookup(pinLookup)
	}
	if r.doh3 != nil {
		r.doh3.SetPinLookup(pinLookup)
	}
	if r.dot != nil {
		r.dot.SetPinLookup(pinLookup)
	}
	if r.doq != nil {
		r.doq.SetPinLookup(pinLookup)
	}

	if r.router != nil {
		r.router.ClearRoutes()
		for pattern, upstream := range cfg.ConditionalRoutes {
			upstream = strings.TrimSpace(upstream)
			if upstream == "" {
				continue
			}
			proto := ProtocolPlain
			server := upstream
			urlStr := ""
			if strings.HasPrefix(upstream, "h3://") {
				proto = ProtocolDoH3
				urlStr = "https://" + strings.TrimPrefix(upstream, "h3://")
			} else if strings.HasPrefix(upstream, "https://") || strings.HasPrefix(upstream, "http://") {
				proto = ProtocolDoH
				urlStr = upstream
			} else if strings.HasPrefix(upstream, "tls://") || strings.HasPrefix(upstream, "dot://") {
				proto = ProtocolDoT
				server = strings.TrimPrefix(strings.TrimPrefix(upstream, "tls://"), "dot://")
			} else if strings.HasPrefix(upstream, "quic://") || strings.HasPrefix(upstream, "doq://") {
				proto = ProtocolDoQ
				server = strings.TrimPrefix(strings.TrimPrefix(upstream, "quic://"), "doq://")
			}
			prov := &ConfiguredProvider{
				ID:       "conditional-" + pattern,
				Protocol: proto,
				Server:   server,
				URL:      urlStr,
				Stats:    NewProviderStats(),
			}
			r.router.SetRoute(pattern, &conditionalProviderAdapter{
				resolver: r,
				provider: prov,
			})
		}
	}

	return nil
}

// Resolve 调度执行 wire-format 二进制 DNS 查询
func (r *CoreResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	req := new(dns.Msg)
	if err := req.Unpack(rawQuery); err == nil && len(req.Question) > 0 && r.router != nil {
		if target := r.router.MatchRoute(req.Question[0].Name); target != nil {
			return target.Resolve(ctx, rawQuery)
		}
	}

	return r.scheduler.resolveWithFallback(ctx, r.fallbackPlan(), rawQuery)
}

// fallbackPlan 汇总当前生效的调度与回退配置
func (r *CoreResolver) fallbackPlan() FallbackPlan {
	r.mu.RLock()
	defer r.mu.RUnlock()

	onError := r.fallbackOnError
	return FallbackPlan{
		Mode:              r.mode,
		Providers:         r.providers,
		FallbackProviders: r.fallbackProviders,
		Timeout:           r.fallbackTimeout,
		OnRcode:           r.fallbackOnRcode,
		OnError:           &onError,
	}
}

// fallbackTimeoutOf 把毫秒配置换算为超时；未配置时采用默认值
func fallbackTimeoutOf(ms int) time.Duration {
	if ms > 0 {
		return time.Duration(ms) * time.Millisecond
	}
	return DefaultFallbackTimeout()
}

// Exchange 调度执行结构化 *dns.Msg 请求并保持 Transaction ID 一致
func (r *CoreResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	if req == nil {
		return nil, fmt.Errorf("nil dns request")
	}

	if len(req.Question) > 0 && r.router != nil {
		if target := r.router.MatchRoute(req.Question[0].Name); target != nil {
			return target.Exchange(ctx, req)
		}
	}

	rawQuery, err := req.Pack()
	if err != nil {
		return nil, fmt.Errorf("pack dns query: %w", err)
	}

	rawResp, err := r.scheduler.resolveWithFallback(ctx, r.fallbackPlan(), rawQuery)
	if err != nil {
		return nil, err
	}

	resp := new(dns.Msg)
	if err := resp.Unpack(rawResp); err != nil {
		return nil, fmt.Errorf("unpack dns response: %w", err)
	}

	resp.Id = req.Id
	return resp, nil
}

type conditionalProviderAdapter struct {
	resolver *CoreResolver
	provider *ConfiguredProvider
}

func (a *conditionalProviderAdapter) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	if a.resolver != nil && a.resolver.scheduler != nil {
		return a.resolver.scheduler.queryWithValidation(ctx, a.provider, rawQuery)
	}
	return a.resolver.executeProvider(ctx, a.provider, rawQuery)
}

func (a *conditionalProviderAdapter) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	raw, err := req.Pack()
	if err != nil {
		return nil, err
	}
	rawResp, err := a.Resolve(ctx, raw)
	if err != nil {
		return nil, err
	}
	resp := new(dns.Msg)
	if err := resp.Unpack(rawResp); err != nil {
		return nil, err
	}
	resp.Id = req.Id
	return resp, nil
}

func (a *conditionalProviderAdapter) Configure(cfg ResolverConfig) error { return nil }
func (a *conditionalProviderAdapter) Shutdown() error                    { return nil }

func (r *CoreResolver) executeProvider(ctx context.Context, p *ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	queryBytes := rawQuery
	r.mu.RLock()
	paddingBlock := r.ednsPadding
	r.mu.RUnlock()

	// 若配置了 EDNS Padding 且为加密传输 (DoH/DoT/DoQ)，按照 RFC 7830 / RFC 8467 对齐填充抹平长度指纹
	if paddingBlock > 0 && p.Protocol.IsEncrypted() {
		var reqMsg dns.Msg
		if err := reqMsg.Unpack(rawQuery); err == nil {
			if PadMessage(&reqMsg, paddingBlock) {
				if packed, pErr := reqMsg.Pack(); pErr == nil {
					queryBytes = packed
				}
			}
		}
	}

	switch p.Protocol {
	case ProtocolDoH:
		return r.doh.Exchange(ctx, queryBytes, p.URL)
	case ProtocolDoH3:
		return r.doh3.Exchange(ctx, queryBytes, p.URL)
	case ProtocolDoT:
		return r.dot.Exchange(ctx, queryBytes, p.Server)
	case ProtocolDoQ:
		return r.doq.Exchange(ctx, queryBytes, p.Server)
	default:
		return r.plain.Exchange(ctx, queryBytes, p.Server)
	}
}

// Shutdown 优雅关闭所有上游连接池
func (r *CoreResolver) Shutdown() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	var firstErr error
	closeAll := func(err error) {
		if err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if r.doh != nil {
		closeAll(r.doh.Close())
	}
	if r.doh3 != nil {
		closeAll(r.doh3.Close())
	}
	if r.dot != nil {
		closeAll(r.dot.Close())
	}
	if r.doq != nil {
		closeAll(r.doq.Close())
	}
	return firstErr
}

// UpstreamStatSnapshot 记录单个上游节点的统计状态快照
type UpstreamStatSnapshot struct {
	ID           string
	Protocol     DNSProtocol
	Server       string
	URL          string
	Weight       int
	SuccessCount uint64
	FailureCount uint64
	AvgLatencyMs float64
	ScoreMs      float64
	IsHealthy    bool
	// PinSet 表示该上游已启用证书固定（不暴露指纹本身，避免泄露无必要信息）
	PinSet bool
}

// PinLookup 返回当前生效的证书固定查询表（未配置固定时返回 nil）。
//
// 供状态展示与上层判断"是否启用了证书固定"。
func (r *CoreResolver) PinLookup() PinLookup {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.pinLookup
}

// GetProviderStats 返回当前配置上游的运行统计指标
func (r *CoreResolver) GetProviderStats() []UpstreamStatSnapshot {
	r.mu.RLock()
	defer r.mu.RUnlock()

	res := make([]UpstreamStatSnapshot, 0, len(r.providers))
	for _, p := range r.providers {
		sampleCount, failureCount, ewmaRTT, score := p.Stats.Snapshot()
		succ := uint64(0)
		if sampleCount > 0 {
			succ = uint64(sampleCount)
		}
		fail := uint64(failureCount)
		res = append(res, UpstreamStatSnapshot{
			ID:           p.ID,
			Protocol:     p.Protocol,
			Server:       p.Server,
			URL:          p.URL,
			Weight:       p.Weight,
			SuccessCount: succ,
			FailureCount: fail,
			AvgLatencyMs: float64(ewmaRTT.Nanoseconds()) / 1e6,
			ScoreMs:      float64(score.Nanoseconds()) / 1e6,
			IsHealthy:    failureCount < 3,
			PinSet:       p.Pin != nil && len(p.Pin.Sha256) > 0,
		})
	}
	return res
}
