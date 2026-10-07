package core

import (
	"strings"
	"sync"
)

// RuleMatcher 封装多层级 Trie、Bloom 预检及正反向规则调度评估器
type RuleMatcher struct {
	mu                  sync.RWMutex
	bloom               *DomainBloomFilter
	blockTrie           *DomainTrie
	importantBlockTrie  *DomainTrie
	allowTrie           *DomainTrie
	importantAllowTrie  *DomainTrie
	regexRules          []*ParsedRule
	wildcardRules       []*ParsedRule
	totalRulesCount     int
}

// NewRuleMatcher 创建规则评估匹配器
func NewRuleMatcher() *RuleMatcher {
	return &RuleMatcher{
		bloom:              NewDomainBloomFilter(1000, 0.001),
		blockTrie:          NewDomainTrie(),
		importantBlockTrie: NewDomainTrie(),
		allowTrie:          NewDomainTrie(),
		importantAllowTrie: NewDomainTrie(),
		regexRules:         make([]*ParsedRule, 0),
		wildcardRules:      make([]*ParsedRule, 0),
	}
}

// BuildFromRules 批量构建索引结构
func (m *RuleMatcher) BuildFromRules(rules []*ParsedRule) {
	m.mu.Lock()
	defer m.mu.Unlock()

	blockTrie := NewDomainTrie()
	importantBlockTrie := NewDomainTrie()
	allowTrie := NewDomainTrie()
	importantAllowTrie := NewDomainTrie()
	var regexes []*ParsedRule
	var wildcards []*ParsedRule

	blockDomains := make([]string, 0, len(rules))

	for _, r := range rules {
		if r == nil {
			continue
		}

		if r.IsRegex {
			regexes = append(regexes, r)
			continue
		}

		if r.IsWildcard {
			wildcards = append(wildcards, r)
			continue
		}

		if r.IsAllow {
			if r.Important {
				importantAllowTrie.Insert(r)
			} else {
				allowTrie.Insert(r)
			}
		} else {
			if r.Important {
				importantBlockTrie.Insert(r)
			} else {
				blockTrie.Insert(r)
			}
			blockDomains = append(blockDomains, r.Pattern)
		}
	}

	// 为所有阻断域名构建 Bloom 预检过滤器
	bloom := NewDomainBloomFilter(len(blockDomains)+10, 0.001)
	for _, d := range blockDomains {
		bloom.Add(d)
	}

	m.bloom = bloom
	m.blockTrie = blockTrie
	m.importantBlockTrie = importantBlockTrie
	m.allowTrie = allowTrie
	m.importantAllowTrie = importantAllowTrie
	m.regexRules = regexes
	m.wildcardRules = wildcards
	m.totalRulesCount = len(rules)
}

// Match 对域名进行多策略优先级匹配评估
func (m *RuleMatcher) Match(domain string, qtype uint16) CheckHostResult {
	m.mu.RLock()
	defer m.mu.RUnlock()

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return CheckHostResult{Action: "pass"}
	}

	// 1. 最高优先级: 带 $important 的白名单例外规则
	if hit, rule := m.importantAllowTrie.Match(domain); hit && matchDNSType(rule, qtype) {
		return CheckHostResult{
			Blocked:     false,
			Action:      "allow",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "important_allow",
		}
	}

	// 2. 次高优先级: 带 $important 的黑名单拦截规则
	if hit, rule := m.importantBlockTrie.Match(domain); hit && matchDNSType(rule, qtype) {
		return CheckHostResult{
			Blocked:     true,
			Action:      "block",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "important_block",
		}
	}

	// 3. 常规白名单例外规则 (@@)
	if hit, rule := m.allowTrie.Match(domain); hit && matchDNSType(rule, qtype) {
		return CheckHostResult{
			Blocked:     false,
			Action:      "allow",
			MatchedRule: rule.Raw,
			ListName:    rule.Source,
			Reason:      "whitelist",
		}
	}

	// 4. Bloom Filter 快速预检
	// 若 Bloom 判定既不存在该域名也不存在其任何父域，可快速跳过 BlockTrie 遍历
	inBloom := true
	if m.bloom != nil && !m.bloom.MightContainDomainOrParent(domain) {
		inBloom = false
	}

	// 5. 常规黑名单 Trie 匹配
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

	// 6. 通配符与正则规则补刀匹配
	for _, rule := range m.wildcardRules {
		if matchDNSType(rule, qtype) && rule.Regex != nil && rule.Regex.MatchString(domain) {
			if rule.IsAllow {
				return CheckHostResult{
					Blocked:     false,
					Action:      "allow",
					MatchedRule: rule.Raw,
					ListName:    rule.Source,
					Reason:      "wildcard_allow",
				}
			}
			return CheckHostResult{
				Blocked:     true,
				Action:      "block",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      "wildcard_block",
			}
		}
	}

	for _, rule := range m.regexRules {
		if matchDNSType(rule, qtype) && rule.Regex != nil && rule.Regex.MatchString(domain) {
			if rule.IsAllow {
				return CheckHostResult{
					Blocked:     false,
					Action:      "allow",
					MatchedRule: rule.Raw,
					ListName:    rule.Source,
					Reason:      "regex_allow",
				}
			}
			return CheckHostResult{
				Blocked:     true,
				Action:      "block",
				MatchedRule: rule.Raw,
				ListName:    rule.Source,
				Reason:      "regex_block",
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

func matchDNSType(rule *ParsedRule, qtype uint16) bool {
	if rule == nil || rule.DNSType == 0 || qtype == 0 {
		return true
	}
	return rule.DNSType == qtype
}
