package core

import (
	"fmt"
	"log"
	"net"
	"sort"
	"strings"
	"sync"
)

// DefaultRewriteTTL 默认重写记录生存期（秒）
const DefaultRewriteTTL uint32 = 60

// RewriteRule 定义单条 DNS 重写/伪装规则
type RewriteRule struct {
	Domain string   `json:"domain"`          // 匹配域名，支持泛域名如 "*.lan" 或精准匹配 "myhost.local"
	IPs    []string `json:"ips,omitempty"`   // A (IPv4) 或 AAAA (IPv6) 解析目标
	CNAME  string   `json:"cname,omitempty"` // CNAME 目标别名
	TXT    []string `json:"txt,omitempty"`   // TXT 记录内容列表
	TTL    uint32   `json:"ttl,omitempty"`   // 生存期（秒），为 0 时使用系统默认 TTL

	// Records 承载 MX / SRV / NS / PTR / HTTPS / SVCB 以及显式写法的 A/AAAA/CNAME/TXT。
	//
	// 与上面的快捷字段并存：快捷字段覆盖了最常见的三种场景，界面默认走快捷字段；
	// Records 用于表达快捷字段无法描述的记录（如 MX 的优先级、SVCB 的 alpn）。
	// 两类同时配置时都会被返回，因此同一条规则可以同时声明 A 与 MX。
	Records []RewriteRecord `json:"records,omitempty"`

	// RCode 覆盖应答码（"NXDOMAIN" / "REFUSED" 等），为空表示 NOERROR。
	//
	// 非 NOERROR 时不再返回任何记录，用于把一个域名整体置为不存在或被拒绝。
	RCode string `json:"rcode,omitempty"`
}

// RewriteConfig DNS 重写配置
type RewriteConfig struct {
	Enabled bool          `json:"enabled"` // 是否启用自定义 DNS 重写与伪装
	TTL     uint32        `json:"ttl"`     // 默认 TTL，默认 60s
	Rules   []RewriteRule `json:"rules"`   // 规则列表
}

// DefaultRewriteConfig 返回默认配置
func DefaultRewriteConfig() RewriteConfig {
	return RewriteConfig{
		Enabled: true,
		TTL:     DefaultRewriteTTL,
		Rules:   []RewriteRule{},
	}
}

// NormalizeRewriteConfig 校验与修补重写配置默认值
func NormalizeRewriteConfig(cfg *RewriteConfig) {
	if cfg == nil {
		return
	}
	if cfg.TTL == 0 {
		cfg.TTL = DefaultRewriteTTL
	}
	if cfg.Rules == nil {
		cfg.Rules = []RewriteRule{}
	}
}

// compiledRule 内部编译后的快速检索结构体
type compiledRule struct {
	domain     string
	isWildcard bool
	suffix     string // 去除 "*." 后的后缀，全小写，不带前后点
	v4List     []net.IP
	v6List     []net.IP
	cname      string // 标准 FQDN (以点结尾)
	txt        []string
	ttl        uint32
	records    []RewriteRecord
	rcode      int
}

// RewriteEngine 自定义 DNS 重写与伪装引擎
// 深度借鉴自 AdGuard Home (dnsrewrite.go)、Blocky (custom_dns_resolver.go) 与 dnscrypt-proxy (plugin_cloak.go)
type RewriteEngine struct {
	mu            sync.RWMutex
	enabled       bool
	defaultTTL    uint32
	exactRules    map[string]*compiledRule // domain -> rule
	wildcardRules []*compiledRule          // 泛域名规则列表（按后缀长度从长到短优先匹配）
	ptrMap        map[string][]string      // ip.String() -> []FQDN domain (支持多别名反向 PTR 解析)
	originalRules []RewriteRule
}

// NewRewriteEngine 创建并初始化 DNS 重写引擎
func NewRewriteEngine(cfg RewriteConfig) *RewriteEngine {
	ttl := cfg.TTL
	if ttl == 0 {
		ttl = DefaultRewriteTTL
	}
	engine := &RewriteEngine{
		enabled:       cfg.Enabled,
		defaultTTL:    ttl,
		exactRules:    make(map[string]*compiledRule),
		wildcardRules: make([]*compiledRule, 0),
		ptrMap:        make(map[string][]string),
		originalRules: make([]RewriteRule, 0),
	}
	for _, rule := range cfg.Rules {
		engine.addRuleInternal(rule)
	}
	return engine
}

// normalizeRewriteDomain 规范化域名字符串为无前后点的小写形式
func normalizeRewriteDomain(domain string) string {
	d := strings.TrimSpace(strings.ToLower(domain))
	return strings.Trim(d, ".")
}

// addRuleInternal 将一条规则编译并加入索引
func (e *RewriteEngine) addRuleInternal(rule RewriteRule) {
	norm := normalizeRewriteDomain(rule.Domain)
	if norm == "" {
		return
	}

	ttl := rule.TTL
	if ttl == 0 {
		ttl = e.defaultTTL
	}

	c := &compiledRule{
		domain: norm,
		ttl:    ttl,
		txt:    rule.TXT,
	}

	// 显式记录在编译期做一次校验并就地剔除非法项：留到查询期才发现只会
	// 让用户看到「配了却不生效」，而编译期可以直接把问题写进日志。
	c.records = compileRewriteRecords(norm, rule.Records)

	// 无法识别的应答码回落到 NOERROR：写错一个单词不该让整条规则变成
	// 一个「什么都不返回」的空壳，那样更难排查。
	if rule.RCode != "" && rule.RCode != RewriteRCodeNone {
		rcode, ok := ParseRewriteRCode(rule.RCode)
		if !ok {
			log.Printf("[Rewrite] 规则 %s 的应答码 %q 无法识别，按 NOERROR 处理", norm, rule.RCode)
		} else {
			c.rcode = rcode
		}
	}

	if strings.HasPrefix(norm, "*.") {
		c.isWildcard = true
		c.suffix = strings.TrimPrefix(norm, "*.")
	}

	if rule.CNAME != "" {
		cname := strings.TrimSpace(rule.CNAME)
		if !strings.HasSuffix(cname, ".") {
			cname += "."
		}
		c.cname = cname
	}

	for _, ipStr := range rule.IPs {
		ip := net.ParseIP(strings.TrimSpace(ipStr))
		if ip == nil {
			continue
		}
		if v4 := ip.To4(); v4 != nil {
			c.v4List = append(c.v4List, v4)
			// 自动建立反向 PTR 映射（精准域名优先，支持多别名）
			if !c.isWildcard {
				e.appendPTR(v4.String(), norm+".")
			}
		} else {
			c.v6List = append(c.v6List, ip)
			if !c.isWildcard {
				e.appendPTR(ip.String(), norm+".")
			}
		}
	}

	e.originalRules = append(e.originalRules, rule)

	if c.isWildcard {
		e.wildcardRules = append(e.wildcardRules, c)
		// 按后缀长度降序排序，长后缀更精确优先匹配
		sort.SliceStable(e.wildcardRules, func(i, j int) bool {
			return len(e.wildcardRules[i].suffix) > len(e.wildcardRules[j].suffix)
		})
	} else {
		e.exactRules[norm] = c
	}
}

// compileRewriteRecords 校验并保留合法的显式记录，丢弃非法项并记录日志
func compileRewriteRecords(domain string, records []RewriteRecord) []RewriteRecord {
	if len(records) == 0 {
		return nil
	}

	kept := make([]RewriteRecord, 0, len(records))
	for _, rec := range records {
		if strings.TrimSpace(rec.Type) == "" {
			continue
		}
		// 用一个中性查询名与类型做试构造：此处只关心取值是否可解析，
		// 与最终返回给哪个查询无关（同名不同类型的记录会在查询期被过滤）。
		rrtype, ok := rewriteRecordTypes[strings.ToUpper(strings.TrimSpace(rec.Type))]
		if !ok {
			log.Printf("[Rewrite] 规则 %s 的记录类型 %q 不受支持，已忽略", domain, rec.Type)
			continue
		}
		if _, err := buildRewriteRR("probe.invalid.", rrtype, rec, DefaultRewriteTTL); err != nil {
			log.Printf("[Rewrite] 规则 %s 的 %s 记录取值非法（%v），已忽略", domain, rec.Type, err)
			continue
		}
		kept = append(kept, rec)
	}
	if len(kept) == 0 {
		return nil
	}
	return kept
}

func (e *RewriteEngine) appendPTR(ipStr, fqdn string) {
	for _, exist := range e.ptrMap[ipStr] {
		if exist == fqdn {
			return
		}
	}
	e.ptrMap[ipStr] = append(e.ptrMap[ipStr], fqdn)
}

func (e *RewriteEngine) findRule(norm string) (*compiledRule, bool) {
	if cr, ok := e.exactRules[norm]; ok {
		return cr, true
	}
	for _, w := range e.wildcardRules {
		if norm == w.suffix || strings.HasSuffix(norm, "."+w.suffix) {
			return w, true
		}
	}
	return nil, false
}

// AddRule 动态添加单条规则
func (e *RewriteEngine) AddRule(rule RewriteRule) error {
	norm := normalizeRewriteDomain(rule.Domain)
	if norm == "" {
		return fmt.Errorf("无效的重写域名")
	}

	e.mu.Lock()
	defer e.mu.Unlock()

	// 检查是否已有同名规则，有则替换
	newRules := make([]RewriteRule, 0, len(e.originalRules)+1)
	for _, r := range e.originalRules {
		if normalizeRewriteDomain(r.Domain) != norm {
			newRules = append(newRules, r)
		}
	}
	newRules = append(newRules, rule)

	e.rebuildRules(newRules)
	return nil
}

// DeleteRule 根据域名删除规则
func (e *RewriteEngine) DeleteRule(domain string) bool {
	norm := normalizeRewriteDomain(domain)
	if norm == "" {
		return false
	}

	e.mu.Lock()
	defer e.mu.Unlock()

	found := false
	newRules := make([]RewriteRule, 0, len(e.originalRules))
	for _, r := range e.originalRules {
		if normalizeRewriteDomain(r.Domain) == norm {
			found = true
			continue
		}
		newRules = append(newRules, r)
	}

	if found {
		e.rebuildRules(newRules)
	}
	return found
}

// rebuildRules 在写锁保护下根据原规则切片全量重建索引
func (e *RewriteEngine) rebuildRules(rules []RewriteRule) {
	e.exactRules = make(map[string]*compiledRule)
	e.wildcardRules = make([]*compiledRule, 0)
	e.ptrMap = make(map[string][]string)
	e.originalRules = make([]RewriteRule, 0, len(rules))

	for _, r := range rules {
		e.addRuleInternal(r)
	}
}

// Configure 整体更新重写配置
func (e *RewriteEngine) Configure(cfg RewriteConfig) {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.enabled = cfg.Enabled
	if cfg.TTL > 0 {
		e.defaultTTL = cfg.TTL
	}
	e.rebuildRules(cfg.Rules)
}

// GetRules 获取当前所有重写规则
func (e *RewriteEngine) GetRules() []RewriteRule {
	e.mu.RLock()
	defer e.mu.RUnlock()

	res := make([]RewriteRule, len(e.originalRules))
	copy(res, e.originalRules)
	return res
}

// IsEnabled 检查重写引擎是否启用
func (e *RewriteEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.enabled
}
