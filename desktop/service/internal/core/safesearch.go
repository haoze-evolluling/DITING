package core

import (
	"net"
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// SafeSearch 服务商标识，与 safesearch_rules.go 中的规则表键一致
const (
	SafeSearchBing       = "bing"
	SafeSearchDuckDuckGo = "duckduckgo"
	SafeSearchEcosia     = "ecosia"
	SafeSearchGoogle     = "google"
	SafeSearchPixabay    = "pixabay"
	SafeSearchYandex     = "yandex"
	SafeSearchYouTube    = "youtube"
)

// DefaultSafeSearchTTL 强制安全搜索应答的默认 TTL（秒）
const DefaultSafeSearchTTL uint32 = 300

// SafeSearchConfig 强制安全搜索配置（默认整体关闭）。
//
// 借鉴自 AdGuard Home internal/filtering/safesearch：将搜索引擎域名重写为
// 提供商的强制过滤入口（多为 CNAME 别名），从 DNS 层保证无法关闭安全搜索。
//
// 服务商采用「黑名单式」表达（Disabled 列出被关闭者，空即全部启用），
// 从而旧版配置缺少 safeSearch 字段时行为自然回落为「全部启用、总开关关闭」。
type SafeSearchConfig struct {
	Enabled  bool     `json:"enabled"`            // 总开关，默认 false
	Disabled []string `json:"disabled,omitempty"` // 已关闭的服务商标识
	TTL      uint32   `json:"ttl"`
}

// SafeSearchServices 返回内置支持的全部服务商标识（顺序稳定，供 UI 展示）
func SafeSearchServices() []string {
	return []string{
		SafeSearchBing,
		SafeSearchDuckDuckGo,
		SafeSearchEcosia,
		SafeSearchGoogle,
		SafeSearchPixabay,
		SafeSearchYandex,
		SafeSearchYouTube,
	}
}

// DefaultSafeSearchConfig 返回默认配置：总开关关闭、服务商全部启用。
func DefaultSafeSearchConfig() SafeSearchConfig {
	return SafeSearchConfig{
		Enabled:  false,
		Disabled: []string{},
		TTL:      DefaultSafeSearchTTL,
	}
}

// NormalizeSafeSearchConfig 校验与修补配置项默认值（过滤非法服务商标识）。
func NormalizeSafeSearchConfig(cfg *SafeSearchConfig) {
	if cfg == nil {
		return
	}
	if cfg.TTL == 0 {
		cfg.TTL = DefaultSafeSearchTTL
	}
	valid := make(map[string]bool)
	for _, s := range SafeSearchServices() {
		valid[s] = true
	}
	seen := make(map[string]bool)
	out := make([]string, 0, len(cfg.Disabled))
	for _, s := range cfg.Disabled {
		if !valid[s] || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	cfg.Disabled = out
}

// SafeSearchResult 安全搜索命中结果
type SafeSearchResult struct {
	Service string // 命中的服务商
	CNAME   string // 重写目标别名（FQDN，带结尾点），无则为空
	IP      net.IP // A/AAAA 重写目标，无则为 nil
	IPType  uint16 // dns.TypeA / dns.TypeAAAA，配合 IP 使用
	NODATA  bool   // 命中但当前查询类型无应答（如 Yandex 的 AAAA 查询），返回空应答
}

// ssRule 编译后的单条安全搜索规则
type ssRule struct {
	domain  string // 小写去点的匹配域名
	service string
	cname   string // FQDN（带结尾点）
	ip      net.IP
	ipType  uint16
}

// SafeSearchEngine 强制安全搜索引擎
type SafeSearchEngine struct {
	mu       sync.RWMutex
	cfg      SafeSearchConfig
	rules    map[string]*ssRule
	disabled map[string]bool
}

// NewSafeSearchEngine 创建并编译强制安全搜索引擎
func NewSafeSearchEngine(cfg SafeSearchConfig) *SafeSearchEngine {
	e := &SafeSearchEngine{
		rules:    make(map[string]*ssRule),
		disabled: make(map[string]bool),
	}
	e.Configure(cfg)
	return e
}

// Configure 全量更新配置并重建规则索引
func (e *SafeSearchEngine) Configure(cfg SafeSearchConfig) {
	if cfg.TTL == 0 {
		cfg.TTL = DefaultSafeSearchTTL
	}
	rules := make(map[string]*ssRule, 512)
	for service, text := range safesearchRuleTexts {
		for _, line := range strings.Split(text, "\n") {
			if r, ok := parseSafeSearchRuleLine(line, service); ok {
				rules[r.domain] = r
			}
		}
	}
	disabled := make(map[string]bool, len(cfg.Disabled))
	for _, s := range cfg.Disabled {
		disabled[s] = true
	}

	e.mu.Lock()
	e.cfg = cfg
	e.rules = rules
	e.disabled = disabled
	e.mu.Unlock()
}

// GetConfig 返回当前配置副本
func (e *SafeSearchEngine) GetConfig() SafeSearchConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.cfg
}

// IsEnabled 返回总开关状态
func (e *SafeSearchEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.cfg.Enabled
}

// serviceEnabledUnlocked 判断某服务商是否已开启（调用方需持锁）
func (e *SafeSearchEngine) serviceEnabledUnlocked(service string) bool {
	return !e.disabled[service]
}

// Lookup 查询域名在给定查询类型下的强制安全搜索改写结果。
//
// 仅在总开关开启、对应服务商开启且查询类型为 A/AAAA/HTTPS 时命中，
// 与 AdGuard Home 的 CheckHost 行为保持一致。
func (e *SafeSearchEngine) Lookup(domain string, qtype uint16) (SafeSearchResult, bool) {
	switch qtype {
	case dns.TypeA, dns.TypeAAAA, dns.TypeHTTPS:
	default:
		return SafeSearchResult{}, false
	}

	norm := normalizeRewriteDomain(domain)
	if norm == "" {
		return SafeSearchResult{}, false
	}

	e.mu.RLock()
	defer e.mu.RUnlock()

	if !e.cfg.Enabled {
		return SafeSearchResult{}, false
	}
	rule, ok := e.rules[norm]
	if !ok || !e.serviceEnabledUnlocked(rule.service) {
		return SafeSearchResult{}, false
	}

	res := SafeSearchResult{Service: rule.service}
	switch {
	case rule.cname != "":
		res.CNAME = rule.cname
	case rule.ip != nil && rule.ipType == qtype:
		res.IP = rule.ip
		res.IPType = rule.ipType
	default:
		// 命中规则但当前查询类型无对应记录（如 Yandex 的 AAAA/HTTPS），返回空应答
		res.NODATA = true
	}
	return res, true
}

// parseSafeSearchRuleLine 解析单条 AdGuard 风格安全搜索规则：
//
//	|domain^$dnsrewrite=NOERROR;CNAME;target
//	|domain^$dnsrewrite=NOERROR;A;213.180.193.56
func parseSafeSearchRuleLine(line, service string) (*ssRule, bool) {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "!") || strings.HasPrefix(line, "#") {
		return nil, false
	}

	domainPart, modPart := line, ""
	if i := strings.Index(line, "$"); i >= 0 {
		domainPart, modPart = line[:i], line[i+1:]
	}
	domain := normalizeRewriteDomain(strings.TrimSuffix(strings.TrimPrefix(domainPart, "|"), "^"))
	if domain == "" || !strings.HasPrefix(modPart, "dnsrewrite=") {
		return nil, false
	}

	parts := strings.SplitN(strings.TrimPrefix(modPart, "dnsrewrite="), ";", 3)
	if len(parts) != 3 {
		return nil, false
	}
	typ := strings.ToUpper(strings.TrimSpace(parts[1]))
	val := strings.TrimSpace(parts[2])

	r := &ssRule{domain: domain, service: service}
	switch typ {
	case "CNAME":
		if val == "" {
			return nil, false
		}
		r.cname = dns.Fqdn(normalizeRewriteDomain(val))
	case "A", "AAAA":
		ip := net.ParseIP(val)
		if ip == nil {
			return nil, false
		}
		if typ == "A" {
			r.ip, r.ipType = ip.To4(), dns.TypeA
		} else {
			r.ip, r.ipType = ip.To16(), dns.TypeAAAA
		}
		if r.ip == nil {
			return nil, false
		}
	default:
		return nil, false
	}
	return r, true
}
