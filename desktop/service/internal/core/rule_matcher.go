package core

// rule_matcher.go is the Go face of the Rust rule index (rust/diting-filter-core).
//
// The tries, the bloom prefilter, the wildcard/regex lists and the `$dnsrewrite` selection all live
// in the kernel; what is left here is the glue: rule encoding for the build, the handle lifecycle
// and turning a rule index back into a `CheckHostResult` (raw line, list name and, for a rewrite,
// the `dns.RR` records Go still knows how to build).
//
// The handle is swapped under the same `sync.RWMutex` the Go implementation used. `Match` holds the
// read lock for the duration of the FFI call so a rebuild cannot free an index that is in use, and
// `BuildFromRules` frees the previous handle under the write lock for the same reason.

import (
	"log"
	"runtime"
	"strings"
	"sync"
	"unsafe"

	"github.com/miekg/dns"
)

// RuleMatcher 封装多层级 Trie、Bloom 预检及正反向规则调度评估器
type RuleMatcher struct {
	mu sync.RWMutex

	// rules 保留规则本体：判定结果只带回规则下标，命中规则原文与来源仍从 Go 侧取。
	rules []*ParsedRule

	// index 为内核中的索引句柄；未构建时为空，Match 直接回落 pass。
	index unsafe.Pointer

	// total 为交给索引的规则条数（含重写与通配规则），与旧实现的 totalRulesCount 一致。
	total int
	// hasDenyAllow 标记是否存在带 $denyallow=/$to= 排除修饰符的规则，由内核构建结果回报。
	hasDenyAllow bool
}

// NewRuleMatcher 创建规则评估匹配器。
//
// 未调用 BuildFromRules 时 Match 一律回落 pass，与旧实现里空索引的行为一致。
// 终结器负责在匹配器被回收时归还内核索引（引擎换索引走 BuildFromRules 的显式释放）。
func NewRuleMatcher() *RuleMatcher {
	matcher := &RuleMatcher{}
	runtime.SetFinalizer(matcher, (*RuleMatcher).release)
	return matcher
}

// BuildFromRules 批量构建索引结构。
//
// 构建失败来自原生内核（库缺失、ABI 不符、载荷损坏），没有第二套实现可以顶上，
// 因此一律向上返回错误：调用方（规则引擎重建、配置热更新）据此让加载失败而不是静默放行。
func (m *RuleMatcher) BuildFromRules(rules []*ParsedRule) error {
	handle, stats, err := filterBuildIndex(filterEncodeRules(rules))
	if err != nil {
		return err
	}
	if stats.uncompiledPatterns > 0 {
		// 规则本身在 Go 侧编译通过，内核却拒绝了同一份模式源：该规则永远不会命中，
		// 记录条数供排查，而不静默丢弃整次加载。
		log.Printf("[RuleMatcher] 有 %d 条通配/正则规则未能在内核中编译，这些规则不会命中",
			stats.uncompiledPatterns)
	}

	m.mu.Lock()
	previous := m.index
	m.index = handle
	m.rules = rules
	m.total = len(rules)
	m.hasDenyAllow = stats.hasDenyAllow
	m.mu.Unlock()

	filterFreeIndex(previous)
	return nil
}

// Match 对域名进行多策略优先级匹配评估 (Important Allow > Important Block > Whitelist Allow > Bloom+Trie Block > Wildcard/Regex)
func (m *RuleMatcher) Match(domain string, qtype uint16) CheckHostResult {
	// 归一化仍在 Go 侧：命中重写时构造 dns.RR 需要同一个名字，跨边界再传一次没有意义。
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return CheckHostResult{Action: "pass"}
	}

	m.mu.RLock()
	handle := m.index
	if handle == nil {
		m.mu.RUnlock()
		return CheckHostResult{Action: "pass"}
	}
	decision, err := filterMatchDomain(handle, domain, qtype)
	if err != nil {
		// 走到这里说明句柄已失效（提前释放或 ABI 错配），属于不可达状态。DNS 过滤失败时
		// 放行比让整个解析器崩掉安全，所以记录后回落 pass，并交给上层日志暴露。
		log.Printf("[RuleMatcher] 原生匹配失败: %v", err)
		m.mu.RUnlock()
		return CheckHostResult{Action: "pass"}
	}
	rules := m.rules
	m.mu.RUnlock()

	return buildHostResult(decision, rules, domain, qtype)
}

// TotalRules 返回已索引规则总数
func (m *RuleMatcher) TotalRules() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.total
}

// release 释放内核索引，供终结器与测试使用。
func (m *RuleMatcher) release() {
	m.mu.Lock()
	handle := m.index
	m.index = nil
	m.rules = nil
	m.mu.Unlock()
	filterFreeIndex(handle)
}

// buildHostResult 把内核判定翻译回 CheckHostResult。
func buildHostResult(decision filterDecision, rules []*ParsedRule, domain string, qtype uint16) CheckHostResult {
	if decision.action == filterActionRewrite && decision.rewrite != nil {
		rule := ruleAt(rules, decision.ruleIndex)
		return rewriteHit(rule, newRewriteResult(decision.rewrite.rcode, rewriteRecords(decision.rewrite.rules, rules, domain, qtype)))
	}

	action := "pass"
	switch decision.action {
	case filterActionAllow:
		action = "allow"
	case filterActionBlock:
		action = "block"
	}
	rule := ruleAt(rules, decision.ruleIndex)
	return CheckHostResult{
		Blocked:     decision.action == filterActionBlock,
		Action:      action,
		MatchedRule: ruleRaw(rule),
		ListName:    ruleSource(rule),
		Reason:      decision.reason,
	}
}

// rewriteRecords 用命中的重写规则构造应答记录：顺序即多条同类型记录的拼接顺序。
func rewriteRecords(indices []int32, rules []*ParsedRule, domain string, qtype uint16) []dns.RR {
	records := make([]dns.RR, 0, len(indices))
	for _, index := range indices {
		rule := ruleAt(rules, index)
		if rule == nil || rule.Rewrite == nil {
			continue
		}
		records = append(records, rule.Rewrite.Records(domain, qtype, DefaultRewriteTTL)...)
	}
	return records
}

func ruleAt(rules []*ParsedRule, index int32) *ParsedRule {
	if index < 0 || int(index) >= len(rules) {
		return nil
	}
	return rules[index]
}

func ruleRaw(rule *ParsedRule) string {
	if rule == nil {
		return ""
	}
	return rule.Raw
}

func ruleSource(rule *ParsedRule) string {
	if rule == nil {
		return ""
	}
	return rule.Source
}
