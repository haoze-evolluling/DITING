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

	for _, r := range rules {
		if r == nil {
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
}

// Match 对域名进行多策略优先级匹配评估 (Important Allow > Important Block > Whitelist Allow > Bloom+Trie Block > Wildcard/Regex)
func (m *RuleMatcher) Match(domain string, qtype uint16) CheckHostResult {
	m.mu.RLock()
	defer m.mu.RUnlock()

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return CheckHostResult{Action: "pass"}
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
	if hit, rule := m.importantBlockTrie.Match(domain); hit && matchDNSType(rule, qtype) {
		return CheckHostResult{
			Blocked:     true,
			Action:      "block",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "important_block",
		}
	}
	for _, rule := range m.importantBlockRules {
		if matchDNSType(rule, qtype) && matchRulePattern(rule, domain) {
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
		if hit, rule := m.blockTrie.Match(domain); hit && matchDNSType(rule, qtype) {
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
		if matchDNSType(rule, qtype) && matchRulePattern(rule, domain) {
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
