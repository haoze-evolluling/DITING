package core

import (
	"fmt"

	"github.com/miekg/dns"
)

// ReasonDNSRewrite 命中 $dnsrewrite 修饰符时的判定原因标识
const ReasonDNSRewrite = "DNSREWRITE"

// RewriteAction 描述一条 $dnsrewrite 修饰符的解析结果（语法对齐 AdGuard Home urlfilter，
// 其 dnsrewrite 规则优先级高于其它规则）：
//
//	$dnsrewrite=1.2.3.4                  简写 → NOERROR;A;1.2.3.4
//	$dnsrewrite=abcd::1234               简写 → NOERROR;AAAA;abcd::1234
//	$dnsrewrite=example.net              简写 → NOERROR;CNAME;example.net
//	$dnsrewrite=REFUSED                  仅应答码，不产出记录
//	$dnsrewrite=NOERROR;TXT;hello_world  显式形式 RCODE;记录类型;取值
//	$dnsrewrite=NOERROR;;                权威 NODATA
//	$dnsrewrite                          裸形式，仅用于例外规则，取消该域名的全部重写
//
// 例外规则 @@||example.com^$dnsrewrite 取消该域名全部重写；
// @@||example.com^$dnsrewrite=1.2.3.4 只取消取值相同的那一条。
//
// 取值语法、取值校验与例外比对的归一化键都在 Rust 内核（rust/diting-rewrite-core/src/action.rs）；
// 这里只保留结构本身、`dns.RR` 构造与展示文案。
type RewriteAction struct {
	// Bare 表示裸 $dnsrewrite（无取值），仅作为例外规则使用
	Bare bool
	// RCode 应答码；Bare 为真时无意义
	RCode int
	// RRType 记录类型；仅在 RCode 为 NOERROR 且存在取值时有效，0 表示不产出记录
	RRType uint16
	// Value 记录取值的原始文本：A/AAAA 为地址，CNAME/PTR 为域名，TXT 为文本
	Value string
}

// rcodeNames 为展示用的应答码反查表。
//
// 解析方向的关键字表在内核里（`action.rs` 复用 `parse_rcode`）：这里只把回传的应答码写成
// `String()` 的文案，不参与任何判定。
var rcodeNames = map[int]string{
	dns.RcodeSuccess:        "NOERROR",
	dns.RcodeFormatError:    "FORMERR",
	dns.RcodeServerFailure:  "SERVFAIL",
	dns.RcodeNameError:      "NXDOMAIN",
	dns.RcodeNotImplemented: "NOTIMP",
	dns.RcodeRefused:        "REFUSED",
}

// String 返回便于查询日志与规则测试面板展示的文本形式
func (a *RewriteAction) String() string {
	if a == nil {
		return ""
	}
	if a.Bare {
		return "$dnsrewrite"
	}
	if a.RCode != dns.RcodeSuccess {
		return rcodeNames[a.RCode]
	}
	if a.RRType == 0 {
		// 显式 NODATA：区分于「完全没有取值」的裸形式
		return "NOERROR;;"
	}
	return fmt.Sprintf("%s %s", dns.TypeToString[a.RRType], a.Value)
}

// key 生成用于例外规则精确比对的规范化键。
//
// 两侧取值可能写法不同（大小写、末尾点、IP 的等价写法），
// 例如 @@||x^$dnsrewrite=127.0.0.1 必须能取消 |x^$dnsrewrite=::ffff:127.0.0.1。
// 归一化与比对都在内核里：这里把内核算出的字符串原样交给规则索引，不在 Go 侧再写一份。
func (a *RewriteAction) key() (string, error) {
	if a == nil {
		return "", nil
	}
	return rewriteActionKey(a)
}

// Records 构造本条重写动作在给定查询名下的应答记录。
//
// 记录构造统一委托给 buildRewriteRR，与自定义重写规则共用同一套类型支持，
// 因此 MX / SRV / HTTPS / SVCB 等取值语法在两种入口下完全一致。
// CNAME 对任意查询类型都返回：别名是名字本身的属性，与请求的记录类型无关。
func (a *RewriteAction) Records(qname string, qtype uint16, ttl uint32) []dns.RR {
	if a == nil || a.Bare || a.RCode != dns.RcodeSuccess || a.RRType == 0 {
		return nil
	}

	rr, err := buildRewriteRR(qname, qtype, RewriteRecord{
		Type:  dns.TypeToString[a.RRType],
		Value: a.Value,
	}, ttl)
	if err != nil || rr == nil {
		return nil
	}
	return []dns.RR{rr}
}

// parseDNSRewriteModifier 解析 $dnsrewrite= 之后的取值。
//
// value 为未经小写化的原文：记录取值与 RCODE 关键字都区分大小写。切分、简写判定与取值校验
// （通过 buildRewriteRR 的同一套类型支持）都在 Rust 内核（action.rs）。
// 解析失败返回错误，调用方据此丢弃整条规则（与非法正则的处理一致）。
func parseDNSRewriteModifier(value string) (*RewriteAction, error) {
	return parseRewriteAction(value)
}
