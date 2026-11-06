package core

import (
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

// rewriteHit 组装重写命中结果。
//
// 命中规则由内核回传的下标反查，理论上必非 nil；这里仍按可空处理，
// 避免一条越界下标把整次查询变成 panic。
func rewriteHit(rule *ParsedRule, res RewriteResult) CheckHostResult {
	return CheckHostResult{
		Blocked:     false,
		Action:      "rewrite",
		MatchedRule: ruleRaw(rule),
		ListName:    ruleSource(rule),
		Reason:      ReasonDNSRewrite,
		Rewritten:   &res,
	}
}
