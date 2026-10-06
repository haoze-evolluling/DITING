package core

import (
	"context"
	"fmt"
	"net/url"
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// DNSProtocol 定义支持的上游传输协议类型
type DNSProtocol string

const (
	ProtocolPlain DNSProtocol = "PLAIN"
	ProtocolDoH   DNSProtocol = "DOH"
	ProtocolDoT   DNSProtocol = "DOT"
)

// ParseProtocol 解析协议字符串
func ParseProtocol(s string) DNSProtocol {
	switch strings.ToUpper(strings.TrimSpace(s)) {
	case "DOH", "HTTPS":
		return ProtocolDoH
	case "DOT", "TLS":
		return ProtocolDoT
	default:
		return ProtocolPlain
	}
}

// ProviderConfig 上游提供者配置结构
type ProviderConfig struct {
	ID       string      `json:"id"`
	Protocol DNSProtocol `json:"protocol"`
	Server   string      `json:"server"` // host:port 格式
	URL      string      `json:"url"`    // DoH URL 地址
	Weight   int         `json:"weight,omitempty"`
}

// ResolverConfig 上游解析器整体配置
type ResolverConfig struct {
	Mode      string           `json:"mode"`
	Providers []ProviderConfig `json:"providers"`
	Bootstrap BootstrapConfig  `json:"bootstrap"`
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
	mu        sync.RWMutex
	mode      string
	providers []*ConfiguredProvider
	bootstrap *BootstrapResolver
	plain     *PlainResolver
	doh       *DoHResolver
	dot       *DoTResolver
	scheduler *Scheduler
}

// NewResolver 创建并初始化核心 DNS 解析器
func NewResolver(cfg ResolverConfig) (*CoreResolver, error) {
	bs := NewBootstrapResolver(cfg.Bootstrap)
	plain := NewPlainResolver(bs)
	doh := NewDoHResolver(bs)
	dot := NewDoTResolver(bs)

	r := &CoreResolver{
		bootstrap: bs,
		plain:     plain,
		doh:       doh,
		dot:       dot,
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

	mode := CanonicalMode(cfg.Mode)
	if mode == ModeSingle && len(cfg.Providers) != 1 {
		// 单节点模式若传入多个提供者，使用第一个
		cfg.Providers = cfg.Providers[:1]
	}

	providers := make([]*ConfiguredProvider, 0, len(cfg.Providers))
	for i, p := range cfg.Providers {
		proto := ParseProtocol(string(p.Protocol))
		if p.ID == "" {
			p.ID = fmt.Sprintf("provider-%d", i+1)
		}

		if proto == ProtocolDoH {
			u, err := url.ParseRequestURI(p.URL)
			if err != nil || u.Scheme != "https" || u.Host == "" {
				return fmt.Errorf("provider %s: invalid DoH URL %q", p.ID, p.URL)
			}
		} else if strings.TrimSpace(p.Server) == "" {
			return fmt.Errorf("provider %s: empty server address", p.ID)
		}

		providers = append(providers, &ConfiguredProvider{
			ID:       p.ID,
			Protocol: proto,
			Server:   p.Server,
			URL:      p.URL,
			Stats:    NewProviderStats(),
		})
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	r.mode = mode
	r.providers = providers
	if r.bootstrap != nil {
		r.bootstrap.UpdateConfig(cfg.Bootstrap)
	}

	return nil
}

// Resolve 调度执行 wire-format 二进制 DNS 查询
func (r *CoreResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	r.mu.RLock()
	mode := r.mode
	providers := r.providers
	r.mu.RUnlock()

	return r.scheduler.Resolve(ctx, mode, providers, rawQuery)
}

// Exchange 调度执行结构化 *dns.Msg 请求并保持 Transaction ID 一致
func (r *CoreResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	if req == nil {
		return nil, fmt.Errorf("nil dns request")
	}

	rawQuery, err := req.Pack()
	if err != nil {
		return nil, fmt.Errorf("pack dns query: %w", err)
	}

	rawResp, err := r.Resolve(ctx, rawQuery)
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

func (r *CoreResolver) executeProvider(ctx context.Context, p *ConfiguredProvider, rawQuery []byte) ([]byte, error) {
	switch p.Protocol {
	case ProtocolDoH:
		return r.doh.Exchange(ctx, rawQuery, p.URL)
	case ProtocolDoT:
		return r.dot.Exchange(ctx, rawQuery, p.Server)
	default:
		return r.plain.Exchange(ctx, rawQuery, p.Server)
	}
}

// Shutdown 优雅关闭所有上游连接池
func (r *CoreResolver) Shutdown() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	var dohErr, dotErr error
	if r.doh != nil {
		dohErr = r.doh.Close()
	}
	if r.dot != nil {
		dotErr = r.dot.Close()
	}

	if dohErr != nil {
		return dohErr
	}
	return dotErr
}
