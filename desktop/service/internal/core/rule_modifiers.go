package core

import "strings"

// ruleExcludesDomain 判断域名是否命中规则的目标域排除集合（$denyallow= / $to=）。
//
// 借鉴自 AdGuard Home urlfilter 修饰符语义：排除集合内的目标域不受本条黑名单规则约束，
// 匹配采用后缀感知（good.ads.com 命中 ads.com），与 Rebinding 白名单判定同款逻辑。
func ruleExcludesDomain(rule *ParsedRule, domain string) bool {
	if rule == nil || domain == "" {
		return false
	}
	return domainMatchesAnySuffix(domain, rule.DenyAllow) ||
		domainMatchesAnySuffix(domain, rule.To)
}

// domainMatchesAnySuffix 判断 domain 是否精确等于后缀集合中的某项，或为其子域。
func domainMatchesAnySuffix(domain string, suffixes []string) bool {
	for _, s := range suffixes {
		if s == "" {
			continue
		}
		if domain == s || strings.HasSuffix(domain, "."+s) {
			return true
		}
	}
	return false
}

// matchRuleApplicable 判定黑名单规则对给定查询是否适用。
//
// 需同时满足：DNS 记录类型约束匹配，且目标域未被 $denyallow=/$to= 排除。
func matchRuleApplicable(rule *ParsedRule, domain string, qtype uint16) bool {
	return matchDNSType(rule, qtype) && !ruleExcludesDomain(rule, domain)
}
