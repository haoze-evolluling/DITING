package core

import (
	"testing"

	"github.com/miekg/dns"
)

// TestParseRuleDenyAllow 校验 $denyallow= 修饰符被解析为排除集合而非整条丢弃。
func TestParseRuleDenyAllow(t *testing.T) {
	rule, ok := ParseRuleLine("||ads.com^$denyallow=ads.com|good.ads.com", "test")
	if !ok || rule == nil {
		t.Fatalf("带 $denyallow= 的规则不应被丢弃")
	}
	if rule.Pattern != "ads.com" {
		t.Fatalf("规则模式解析错误: %q", rule.Pattern)
	}
	if len(rule.DenyAllow) != 2 || rule.DenyAllow[0] != "ads.com" || rule.DenyAllow[1] != "good.ads.com" {
		t.Fatalf("排除集合解析错误: %v", rule.DenyAllow)
	}
	if len(rule.To) != 0 {
		t.Fatalf("不应解析出 $to= 条目: %v", rule.To)
	}
}

// TestParseRuleToModifier 校验 $to= 修饰符按目标域限定解析。
func TestParseRuleToModifier(t *testing.T) {
	rule, ok := ParseRuleLine("||tracker.com^$to=example.com|~sub.example.com", "test")
	if !ok || rule == nil {
		t.Fatalf("带 $to= 的规则不应被丢弃")
	}
	// 取反条目（~sub.example.com）在 DNS 层无可靠等价语义，应被跳过
	if len(rule.To) != 1 || rule.To[0] != "example.com" {
		t.Fatalf("$to= 解析错误: %v", rule.To)
	}
}

// TestParseRuleDenyAllowNormalization 校验排除条目的去点、小写与前缀清洗。
func TestParseRuleDenyAllowNormalization(t *testing.T) {
	rule, ok := ParseRuleLine("||ads.com^$denyallow=*.Good.Ads.COM.", "test")
	if !ok || rule == nil {
		t.Fatalf("规则解析失败")
	}
	if len(rule.DenyAllow) != 1 || rule.DenyAllow[0] != "good.ads.com" {
		t.Fatalf("排除条目规范化错误: %v", rule.DenyAllow)
	}
}

// TestRuleMatcherDenyAllowExclusion 校验排除集合内的域名不再被该条规则拦截。
func TestRuleMatcherDenyAllowExclusion(t *testing.T) {
	rules := []*ParsedRule{
		{
			Raw:       "||ads.com^$denyallow=good.ads.com",
			Pattern:   "ads.com",
			DenyAllow: []string{"good.ads.com"},
		},
	}
	matcher := NewRuleMatcher()
	matcher.BuildFromRules(rules)

	if !matcher.hasDenyAllow {
		t.Fatalf("存在 $denyallow= 规则时 hasDenyAllow 应为 true")
	}

	// 排除集合内（含子域）：放行
	for _, d := range []string{"good.ads.com", "sub.good.ads.com"} {
		res := matcher.Match(d, dns.TypeA)
		if res.Blocked {
			t.Fatalf("%s 处于 $denyallow= 排除集合内，不应被拦截: %+v", d, res)
		}
		if res.Action != "pass" {
			t.Fatalf("%s 应回落 pass，得到 %s", d, res.Action)
		}
	}

	// 排除集合外：正常拦截
	for _, d := range []string{"ads.com", "bad.ads.com"} {
		res := matcher.Match(d, dns.TypeA)
		if !res.Blocked || res.Reason != "blacklist" {
			t.Fatalf("%s 应被黑名单拦截，得到 %+v", d, res)
		}
	}
}

// TestRuleMatcherDenyAllowPriorityFallback 校验被排除的高优先级规则会向下回落到较低层级规则。
func TestRuleMatcherDenyAllowPriorityFallback(t *testing.T) {
	rules := []*ParsedRule{
		// 重要黑名单：排除 cdn.example.com
		{
			Raw:       "||example.com^$important,denyallow=cdn.example.com",
			Pattern:   "example.com",
			Important: true,
			DenyAllow: []string{"cdn.example.com"},
		},
		// 常规黑名单：无排除修饰符
		{Raw: "||cdn.example.com^", Pattern: "cdn.example.com"},
	}
	matcher := NewRuleMatcher()
	matcher.BuildFromRules(rules)

	// 重要规则被排除后，应回落到常规黑名单规则继续拦截
	res := matcher.Match("cdn.example.com", dns.TypeA)
	if !res.Blocked || res.Reason != "blacklist" {
		t.Fatalf("排除重要规则后应回落常规黑名单，得到 %+v", res)
	}

	// 其余子域仍由重要规则拦截
	res = matcher.Match("other.example.com", dns.TypeA)
	if !res.Blocked || res.Reason != "important_block" {
		t.Fatalf("other.example.com 应由重要规则拦截，得到 %+v", res)
	}
}

// TestRuleMatcherNoDenyAllowZeroOverhead 校验无排除修饰符时快速通道标记为 false。
func TestRuleMatcherNoDenyAllowZeroOverhead(t *testing.T) {
	matcher := NewRuleMatcher()
	matcher.BuildFromRules([]*ParsedRule{{Raw: "||ads.com^", Pattern: "ads.com"}})
	if matcher.hasDenyAllow {
		t.Fatalf("无 $denyallow=/$to= 规则时 hasDenyAllow 应为 false")
	}
}

// TestRuleExcludesDomain 校验后缀感知排除判定。
func TestRuleExcludesDomain(t *testing.T) {
	rule := &ParsedRule{DenyAllow: []string{"trusted.com"}, To: []string{"partner.net"}}
	cases := map[string]bool{
		"trusted.com":       true,
		"a.trusted.com":     true,
		"partner.net":       true,
		"a.partner.net":     true,
		"untrusted.com":     false,
		"nottrusted.com":    false, // 后缀边界必须落在标签上
		"other.example.com": false,
	}
	for domain, want := range cases {
		if got := ruleExcludesDomain(rule, domain); got != want {
			t.Errorf("ruleExcludesDomain(%q) = %v, 期望 %v", domain, got, want)
		}
	}
}
