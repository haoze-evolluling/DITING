package core

import (
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// RuleMatcher 封装多层级 Trie、Bloom 预检及正反向规则调度评估器
type RuleMatcher struct {
	mu sync.RWMutex

	// Tier 1: 带 $important 的白名单例外规则
	importantAllowTrie  *DomainTrie
	importantAllowRules []*ParsedRule

	// Tier 2: 带 $important 的黑名单拦截规则
	importantBlockTrie  *DomainTrie
	importantBlockRules []*ParsedRule

	// Tier 3: 常规白名单例外规则 (@@)
	allowTrie  *DomainTrie
	allowRules []*ParsedRule

	// Tier 4: 常规黑名单拦截规则 (Bloom 预检 + Trie + 通配符/正则)
	bloom           *DomainBloomFilter
	blockTrie       *DomainTrie
	blockRules      []*ParsedRule
	totalRulesCount int

	// hasDenyAllow 标记是否存在带 $denyallow=/$to= 排除修饰符的规则。
	// 为 false 时匹配热路径完全跳过排除判定，零额外开销。
	hasDenyAllow bool

	// Tier 0: $dnsrewrite 重写规则（优先级高于一切拦截与放行规则）
	//
	// 按域名分桶而非直接建 Trie：重写规则是「精确名字 → 应答内容」的映射，
	// 查询时需要把一个域名的全部重写规则一并取出（多条 A 记录求和），
	// 字典树只能给出单条命中，语义不符。向上逐级查找保留了父域继承的写法。
	rewriteExact   map[string][]*ParsedRule
	rewriteWild    []*ParsedRule // 通配符与正则形式的重写规则
	rewriteCancels []*ParsedRule // 例外规则上的 $dnsrewrite，用于取消重写
}

// NewRuleMatcher 创建规则评估匹配器
func NewRuleMatcher() *RuleMatcher {
	return &RuleMatcher{
		importantAllowTrie:  NewDomainTrie(),
		importantAllowRules: make([]*ParsedRule, 0),
		importantBlockTrie:  NewDomainTrie(),
		importantBlockRules: make([]*ParsedRule, 0),
		allowTrie:           NewDomainTrie(),
		allowRules:          make([]*ParsedRule, 0),
		bloom:               NewDomainBloomFilter(1000, 0.001),
		blockTrie:           NewDomainTrie(),
		blockRules:          make([]*ParsedRule, 0),
		rewriteExact:        make(map[string][]*ParsedRule),
	}
}

// BuildFromRules 批量构建索引结构
func (m *RuleMatcher) BuildFromRules(rules []*ParsedRule) {
	m.mu.Lock()
	defer m.mu.Unlock()

	importantAllowTrie := NewDomainTrie()
	var importantAllowRules []*ParsedRule

	importantBlockTrie := NewDomainTrie()
	var importantBlockRules []*ParsedRule

	allowTrie := NewDomainTrie()
	var allowRules []*ParsedRule

	blockTrie := NewDomainTrie()
	var blockRules []*ParsedRule

	blockDomains := make([]string, 0, len(rules))

	// 是否出现带 $denyallow=/$to= 排除修饰符的黑名单规则
	hasDenyAllow := false

	rewriteExact := make(map[string][]*ParsedRule)
	var rewriteWild []*ParsedRule
	var rewriteCancels []*ParsedRule

	for _, r := range rules {
		if r == nil {
			continue
		}

		// Tier 0: 重写规则从拦截/放行索引中完全剥离。
		//
		// 例外规则上的裸 $dnsrewrite 只用于取消重写，若同时留在放行 Trie 中，
		// 会让"取消一条重写"变成"整域放行"，把该域名下的黑名单规则一并解除。
		if r.Rewrite != nil {
			switch {
			case r.IsAllow:
				rewriteCancels = append(rewriteCancels, r)
			case r.IsRegex || r.IsWildcard:
				rewriteWild = append(rewriteWild, r)
			default:
				rewriteExact[r.Pattern] = append(rewriteExact[r.Pattern], r)
			}
			continue
		}

		if r.IsAllow {
			if r.Important {
				if r.IsRegex || r.IsWildcard {
					importantAllowRules = append(importantAllowRules, r)
				} else {
					importantAllowTrie.Insert(r)
				}
			} else {
				if r.IsRegex || r.IsWildcard {
					allowRules = append(allowRules, r)
				} else {
					allowTrie.Insert(r)
				}
			}
		} else {
			if len(r.DenyAllow) > 0 || len(r.To) > 0 {
				hasDenyAllow = true
			}
			if r.Important {
				if r.IsRegex || r.IsWildcard {
					importantBlockRules = append(importantBlockRules, r)
				} else {
					importantBlockTrie.Insert(r)
					blockDomains = append(blockDomains, r.Pattern)
				}
			} else {
				if r.IsRegex || r.IsWildcard {
					blockRules = append(blockRules, r)
				} else {
					blockTrie.Insert(r)
					blockDomains = append(blockDomains, r.Pattern)
				}
			}
		}
	}

	// 为所有阻断域名构建 Bloom 预检过滤器
	bloom := NewDomainBloomFilter(len(blockDomains)+10, 0.001)
	for _, d := range blockDomains {
		bloom.Add(d)
	}

	m.importantAllowTrie = importantAllowTrie
	m.importantAllowRules = importantAllowRules
	m.importantBlockTrie = importantBlockTrie
	m.importantBlockRules = importantBlockRules
	m.allowTrie = allowTrie
	m.allowRules = allowRules
	m.bloom = bloom
	m.blockTrie = blockTrie
	m.blockRules = blockRules
	m.totalRulesCount = len(rules)
	m.hasDenyAllow = hasDenyAllow
	m.rewriteExact = rewriteExact
	m.rewriteWild = rewriteWild
	m.rewriteCancels = rewriteCancels
}

// Match 对域名进行多策略优先级匹配评估 (Important Allow > Important Block > Whitelist Allow > Bloom+Trie Block > Wildcard/Regex)
func (m *RuleMatcher) Match(domain string, qtype uint16) CheckHostResult {
	m.mu.RLock()
	defer m.mu.RUnlock()

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return CheckHostResult{Action: "pass"}
	}

	// 0. 最高优先级: $dnsrewrite 重写规则
	//
	// 对齐 AdGuard Home：重写先于一切拦截与放行判定。未命中时零开销，
	// 因此不需要额外的 hasRewrite 开关。
	if res, hit := m.matchRewriteUnlocked(domain, qtype); hit {
		return res
	}

	// 1. 最高优先级: 带 $important 的白名单例外规则 (Trie -> Wildcard/Regex)
	if hit, rule := m.importantAllowTrie.Match(domain); hit && matchDNSType(rule, qtype) {
		return CheckHostResult{
			Blocked:     false,
			Action:      "allow",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "important_allow",
		}
	}
	for _, rule := range m.importantAllowRules {
		if matchDNSType(rule, qtype) && matchRulePattern(rule, domain) {
			return CheckHostResult{
				Blocked:     false,
				Action:      "allow",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      "important_allow",
			}
		}
	}

	// 2. 次高优先级: 带 $important 的黑名单拦截规则 (Trie -> Wildcard/Regex)
	if hit, rule := m.importantBlockTrie.Match(domain); hit && matchRuleApplicable(rule, domain, qtype) {
		return CheckHostResult{
			Blocked:     true,
			Action:      "block",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "important_block",
		}
	}
	for _, rule := range m.importantBlockRules {
		if matchRuleApplicable(rule, domain, qtype) && matchRulePattern(rule, domain) {
			return CheckHostResult{
				Blocked:     true,
				Action:      "block",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      "important_block",
			}
		}
	}

	// 3. 第三优先级: 常规白名单例外规则 (@@) (Trie -> Wildcard/Regex)
	if hit, rule := m.allowTrie.Match(domain); hit && matchDNSType(rule, qtype) {
		return CheckHostResult{
			Blocked:     false,
			Action:      "allow",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "whitelist",
		}
	}
	for _, rule := range m.allowRules {
		if matchDNSType(rule, qtype) && matchRulePattern(rule, domain) {
			return CheckHostResult{
				Blocked:     false,
				Action:      "allow",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      "whitelist",
			}
		}
	}

	// 4. 第四优先级: 常规黑名单 Trie 拦截规则 (前置 BloomFilter 纳秒预检)
	inBloom := true
	if m.bloom != nil && !m.bloom.MightContainDomainOrParent(domain) {
		inBloom = false
	}
	if inBloom {
		if hit, rule := m.blockTrie.Match(domain); hit && matchRuleApplicable(rule, domain, qtype) {
			return CheckHostResult{
				Blocked:     true,
				Action:      "block",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      "blacklist",
			}
		}
	}

	// 5. 第五优先级: 常规黑名单通配符与正则规则
	for _, rule := range m.blockRules {
		if matchRuleApplicable(rule, domain, qtype) && matchRulePattern(rule, domain) {
			reason := "wildcard_block"
			if rule.IsRegex {
				reason = "regex_block"
			}
			return CheckHostResult{
				Blocked:     true,
				Action:      "block",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      reason,
			}
		}
	}

	return CheckHostResult{
		Blocked: false,
		Action:  "pass",
	}
}

// TotalRules 返回已索引规则总数
func (m *RuleMatcher) TotalRules() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.totalRulesCount
}

func matchRulePattern(rule *ParsedRule, domain string) bool {
	if rule == nil {
		return false
	}
	if rule.Regex != nil {
		return rule.Regex.MatchString(domain)
	}
	return false
}

func matchDNSType(rule *ParsedRule, qtype uint16) bool {
	if rule == nil || rule.DNSType == 0 || qtype == 0 || qtype == dns.TypeANY {
		return true
	}
	return rule.DNSType == qtype
}
