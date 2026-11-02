package core

import (
	"strings"

	"github.com/miekg/dns"
)

// RewriteResult 描述 $dnsrewrite 规则给出的应答内容。
//
// 与 RewriteAction 的区别：RewriteAction 是「规则怎么说」，
// RewriteResult 是「这次查询实际返回什么」，已按查询名与记录类型展开成记录。
type RewriteResult struct {
	// RCode 应答码；非 NOERROR 时 Records 必为空
	RCode int `json:"rcode"`
	// Records 应答记录，NOERROR 下可能为空（显式 NODATA）
	//
	// 不参与 JSON 序列化：这是给 DNS 应答用的运行时结构，
	// 对外展示走 Summary（记录本身的字符串形式更贴近用户预期）。
	Records []dns.RR `json:"-"`
	// Summary 为 Records 的展示形式，供规则测试面板与查询日志直接呈现
	Summary []string `json:"summary,omitempty"`
}

// newRewriteResult 组装结果并同步生成展示形式
func newRewriteResult(rcode int, records []dns.RR) RewriteResult {
	res := RewriteResult{RCode: rcode, Records: records}
	for _, rr := range records {
		res.Summary = append(res.Summary, rr.String())
	}
	return res
}

// collectRewriteRulesUnlocked 收集与该域名匹配的全部重写规则（调用方须持有读锁）。
//
// 逐级向上查找以保留字典树的「父域继承」语义；标记为精确匹配的规则不参与继承。
func (m *RuleMatcher) collectRewriteRulesUnlocked(domain string) []*ParsedRule {
	if len(m.rewriteExact) == 0 && len(m.rewriteWild) == 0 {
		return nil
	}

	var out []*ParsedRule
	name := domain
	for {
		for _, r := range m.rewriteExact[name] {
			if !r.IsExact || r.Pattern == domain {
				out = append(out, r)
			}
		}
		idx := strings.IndexByte(name, '.')
		if idx < 0 {
			break
		}
		name = name[idx+1:]
	}

	for _, r := range m.rewriteWild {
		if matchRulePattern(r, domain) {
			out = append(out, r)
		}
	}
	return out
}

// rewriteRuleMatches 判断一条取消规则是否作用于该域名
func rewriteRuleMatches(rule *ParsedRule, domain string) bool {
	if rule == nil {
		return false
	}
	if rule.IsRegex || rule.IsWildcard {
		return matchRulePattern(rule, domain)
	}
	if rule.Pattern == domain {
		return true
	}
	if rule.IsExact {
		return false
	}
	return strings.HasSuffix(domain, "."+rule.Pattern)
}

// applyRewriteCancelsUnlocked 应用例外规则中的 $dnsrewrite 取消重写规则（调用方须持有读锁）。
//
// 裸形式取消该域名的全部重写，带取值的形式只取消取值相同的那一条；
// 这两类规则一律不参与放行判定，否则「只取消一条重写」会被误当成整域放行。
func (m *RuleMatcher) applyRewriteCancelsUnlocked(rules []*ParsedRule, domain string) []*ParsedRule {
	if len(m.rewriteCancels) == 0 || len(rules) == 0 {
		return rules
	}

	kept := rules
	for _, c := range m.rewriteCancels {
		if c.Rewrite == nil || !rewriteRuleMatches(c, domain) {
			continue
		}
		if c.Rewrite.Bare {
			return nil
		}
		want := c.Rewrite.key()
		next := make([]*ParsedRule, 0, len(kept))
		for _, r := range kept {
			if r.Rewrite != nil && r.Rewrite.key() == want {
				continue
			}
			next = append(next, r)
		}
		kept = next
	}
	return kept
}

// matchRewriteUnlocked 评估重写规则，未命中任何规则时返回 false。
//
// 优先级（对齐 AdGuard Home 的 processDNSRewrites）：
//  1. 非 NOERROR 的应答码优先于一切记录 —— 明确的失败应答比伪造成功应答更安全；
//  2. CNAME 优先于其它记录类型 —— 别名是名字本身的属性，客户端拿到才能继续解析；
//  3. 其余同类型记录合并进同一应答（多条 A 记录求和）。
func (m *RuleMatcher) matchRewriteUnlocked(domain string, qtype uint16) (CheckHostResult, bool) {
	rules := m.applyRewriteCancelsUnlocked(m.collectRewriteRulesUnlocked(domain), domain)
	if len(rules) == 0 {
		return CheckHostResult{}, false
	}

	for _, r := range rules {
		if r.Rewrite.RCode != dns.RcodeSuccess {
			return rewriteHit(r, newRewriteResult(r.Rewrite.RCode, nil)), true
		}
	}

	for _, r := range rules {
		if r.Rewrite.RRType != dns.TypeCNAME {
			continue
		}
		records := r.Rewrite.Records(domain, qtype, DefaultRewriteTTL)
		return rewriteHit(r, newRewriteResult(dns.RcodeSuccess, records)), true
	}

	var records []dns.RR
	first := rules[0]
	for _, r := range rules {
		if r.Rewrite.RRType != qtype {
			continue
		}
		records = append(records, r.Rewrite.Records(domain, qtype, DefaultRewriteTTL)...)
	}

	// 命中重写但无该类型的记录：返回权威 NODATA，杜绝该名字外泄到上游
	return rewriteHit(first, newRewriteResult(dns.RcodeSuccess, records)), true
}

// rewriteHit 组装重写命中结果
func rewriteHit(rule *ParsedRule, res RewriteResult) CheckHostResult {
	return CheckHostResult{
		Blocked:     false,
		Action:      "rewrite",
		MatchedRule: rule.Raw,
		ListName:    rule.Source,
		Reason:      ReasonDNSRewrite,
		Rewritten:   &res,
	}
}
