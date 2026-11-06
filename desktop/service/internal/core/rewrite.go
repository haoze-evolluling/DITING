package core

import (
	"fmt"
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

// RewriteEngine 自定义 DNS 重写与伪装引擎
// 深度借鉴自 AdGuard Home (dnsrewrite.go)、Blocky (custom_dns_resolver.go) 与 dnscrypt-proxy (plugin_cloak.go)
//
// 索引、匹配与记录构造都在 Rust 内核（rust/diting-rewrite-core）里：Go 只保留配置本身
// （IPC 的 JSON 形态与增删改），每次变更整体重建一份快照句柄并原子换新。
type RewriteEngine struct {
	mu         sync.RWMutex
	enabled    bool
	defaultTTL uint32
	rules      []RewriteRule
	native     *rewriteEngineHandle
}

// NewRewriteEngine 创建并初始化 DNS 重写引擎
//
// 内核缺失、ABI 不匹配或载荷被拒都会让构造失败，调用方（服务启动）随之报错；不会退化成
// “规则静默不生效”的空引擎。
func NewRewriteEngine(cfg RewriteConfig) (*RewriteEngine, error) {
	ttl := cfg.TTL
	if ttl == 0 {
		ttl = DefaultRewriteTTL
	}
	engine := &RewriteEngine{
		enabled:    cfg.Enabled,
		defaultTTL: ttl,
	}
	if err := engine.swap(retainRewriteRules(cfg.Rules), cfg.Enabled, ttl); err != nil {
		return nil, err
	}
	return engine, nil
}

// normalizeRewriteDomain 规范化域名字符串为无前后点的小写形式
func normalizeRewriteDomain(domain string) string {
	d := strings.TrimSpace(strings.ToLower(domain))
	return strings.Trim(d, ".")
}

// retainRewriteRules 丢掉规范化后为空的规则，与旧 addRuleInternal 的行为一致：
// 这些规则既不进索引，也不出现在 GetRules 的返回值里。
func retainRewriteRules(rules []RewriteRule) []RewriteRule {
	kept := make([]RewriteRule, 0, len(rules))
	for _, rule := range rules {
		if normalizeRewriteDomain(rule.Domain) != "" {
			kept = append(kept, rule)
		}
	}
	return kept
}

// rebuild 用当前的启用状态与默认 TTL 编译一份新快照。
//
// 调用方必须持有写锁（构造期除外）。旧句柄在换新后释放：写锁已经排除了所有在途的读者。
func (e *RewriteEngine) rebuild(rules []RewriteRule) error {
	return e.swap(rules, e.enabled, e.defaultTTL)
}

// swap 编译 rules 并在成功后整体换新；失败时旧快照与原状态完全保留。
func (e *RewriteEngine) swap(rules []RewriteRule, enabled bool, ttl uint32) error {
	handle, err := buildRewriteEngine(RewriteConfig{Enabled: enabled, TTL: ttl, Rules: rules})
	if err != nil {
		return err
	}
	old := e.native
	e.native = handle
	e.rules = rules
	e.enabled = enabled
	e.defaultTTL = ttl
	if old != nil {
		old.free()
	}
	return nil
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
	newRules := make([]RewriteRule, 0, len(e.rules)+1)
	for _, r := range e.rules {
		if normalizeRewriteDomain(r.Domain) != norm {
			newRules = append(newRules, r)
		}
	}
	newRules = append(newRules, rule)
	return e.rebuild(newRules)
}

// DeleteRule 根据域名删除规则。第二个返回值表示是否找到，失败时快照保持不变。
func (e *RewriteEngine) DeleteRule(domain string) (bool, error) {
	norm := normalizeRewriteDomain(domain)
	if norm == "" {
		return false, nil
	}

	e.mu.Lock()
	defer e.mu.Unlock()

	found := false
	newRules := make([]RewriteRule, 0, len(e.rules))
	for _, r := range e.rules {
		if normalizeRewriteDomain(r.Domain) == norm {
			found = true
			continue
		}
		newRules = append(newRules, r)
	}
	if !found {
		return false, nil
	}
	if err := e.rebuild(newRules); err != nil {
		return false, err
	}
	return true, nil
}

// Configure 整体更新重写配置
func (e *RewriteEngine) Configure(cfg RewriteConfig) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	ttl := e.defaultTTL
	if cfg.TTL > 0 {
		ttl = cfg.TTL
	}
	return e.swap(retainRewriteRules(cfg.Rules), cfg.Enabled, ttl)
}

// GetRules 获取当前所有重写规则
func (e *RewriteEngine) GetRules() []RewriteRule {
	e.mu.RLock()
	defer e.mu.RUnlock()

	res := make([]RewriteRule, len(e.rules))
	copy(res, e.rules)
	return res
}

// IsEnabled 检查重写引擎是否启用
func (e *RewriteEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.enabled
}
