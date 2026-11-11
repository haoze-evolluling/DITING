package core

import (
	"strings"

	"github.com/miekg/dns"
)

// MaxResponseAliasDepth 响应侧别名链复检的最大候选域名数量。
//
// 借鉴自 dnscrypt-proxy plugin_block_name.go：对 CNAME 别名链设置上限，
// 防止超长链或环形别名拖垮 DNS 热路径。
const MaxResponseAliasDepth = 8

// ReasonResponseBlocked 响应侧别名链命中拦截规则时的判定原因标识
const ReasonResponseBlocked = "RESPONSE_CNAME_BLOCKED"

// ExtractResponseCheckNames 抽取响应 Answer 中需要二次复检的候选域名。
//
// 覆盖两类：CNAME 别名目标（CDN 换域、跳转器绕过 QNAME 拦截的主要途径），
// 以及 A/AAAA 记录所属名（通配符合成或别名链末端的记录名）。
// 返回结果已去重、去点、小写，并排除查询名本身与超出 MaxResponseAliasDepth 的条目。
func ExtractResponseCheckNames(resp *dns.Msg, qname string) []string {
	if resp == nil || len(resp.Answer) == 0 {
		return nil
	}

	origin := normalizeCheckName(qname)
	seen := make(map[string]bool, MaxResponseAliasDepth)
	names := make([]string, 0, MaxResponseAliasDepth)

	add := func(raw string) {
		name := normalizeCheckName(raw)
		if name == "" || name == origin || seen[name] {
			return
		}
		if len(names) >= MaxResponseAliasDepth {
			return
		}
		seen[name] = true
		names = append(names, name)
	}

	for _, rr := range resp.Answer {
		switch v := rr.(type) {
		case *dns.CNAME:
			add(v.Target)
		case *dns.A:
			add(v.Hdr.Name)
		case *dns.AAAA:
			add(v.Hdr.Name)
		case *dns.HTTPS:
			add(v.Hdr.Name)
		case *dns.SVCB:
			add(v.Hdr.Name)
		}
		if len(names) >= MaxResponseAliasDepth {
			break
		}
	}
	return names
}

// normalizeCheckName 将域名规范化用于复检比较（小写、去尾点、去空白）。
func normalizeCheckName(name string) string {
	return strings.TrimSuffix(strings.ToLower(strings.TrimSpace(name)), ".")
}

// MatchResponse 对响应报文中的别名链与记录所属名执行组感知规则复检。
//
// 与 MatchForGroup 的区别：不递增查询统计指标（一次查询只应计一次），
// 返回首个命中的拦截结果；未命中任何候选域名时返回 pass。
func (e *RuleEngine) MatchResponse(resp *dns.Msg, qname string, qtype uint16, groupID string) CheckHostResult {
	if e == nil || !e.IsEnabled() {
		return CheckHostResult{Action: "pass"}
	}
	// 门控必须与请求侧 MatchForGroup 用同一把尺子：全局计划静默、某分组计划
	// 活跃时，该分组的响应侧复检仍要跑（否则 CNAME 换域投毒漏拦）；反向的
	// 分组静默期也不该在响应侧被拦。
	if !e.IsBlockingActiveForGroup(groupID) {
		return CheckHostResult{Action: "pass", Reason: ReasonScheduleInactive}
	}

	names := ExtractResponseCheckNames(resp, qname)
	if len(names) == 0 {
		return CheckHostResult{Action: "pass"}
	}

	matcher := e.getGroupMatcher(groupID)
	if matcher == nil {
		return CheckHostResult{Action: "pass"}
	}

	for _, name := range names {
		res := matcher.Match(name, qtype)
		if res.Blocked {
			res.Reason = ReasonResponseBlocked
			return res
		}
	}
	return CheckHostResult{Action: "pass"}
}
