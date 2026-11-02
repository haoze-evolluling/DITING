package core

import (
	"fmt"
	"net"
	"strings"

	"github.com/miekg/dns"
	"golang.org/x/net/idna"
)

// ReasonDNSRewrite 命中 $dnsrewrite 修饰符时的判定原因标识
const ReasonDNSRewrite = "DNSREWRITE"

// RewriteAction 描述一条 $dnsrewrite 修饰符的解析结果。
//
// 语法对齐 AdGuard Home urlfilter（其文档明确 dnsrewrite 规则优先级高于其它规则）：
//
//	$dnsrewrite=1.2.3.4                  简写 → NOERROR;A;1.2.3.4
//	$dnsrewrite=abcd::1234               简写 → NOERROR;AAAA;abcd::1234
//	$dnsrewrite=example.net              简写 → NOERROR;CNAME;example.net
//	$dnsrewrite=REFUSED                  仅应答码，不产出记录
//	$dnsrewrite=NOERROR;TXT;hello_world  显式形式 RCODE;记录类型;取值
//	$dnsrewrite=NOERROR;;                显式声明该名字无任何记录（权威 NODATA）
//	$dnsrewrite                          裸形式，仅用于例外规则，取消该域名的全部重写
//
// 例外规则 @@||example.com^$dnsrewrite 取消该域名全部重写；
// @@||example.com^$dnsrewrite=1.2.3.4 只取消取值相同的那一条。
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

// rcodeKeywords 支持的 RCODE 关键字。
//
// 官方文档要求关键字全大写，这里放宽为大小写不敏感：取值位置出现一个
// 点分隔域名时不可能与这些单词混淆（"refused" 这类单标签名字本就不会被解析为域名）。
var rcodeKeywords = map[string]int{
	"NOERROR":  dns.RcodeSuccess,
	"FORMERR":  dns.RcodeFormatError,
	"SERVFAIL": dns.RcodeServerFailure,
	"NXDOMAIN": dns.RcodeNameError,
	"NOTIMP":   dns.RcodeNotImplemented,
	"REFUSED":  dns.RcodeRefused,
}

// rcodeNames 为 rcodeKeywords 的反查表，用于展示
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
// 例如 @@||x^$dnsrewrite=127.0.0.1 必须能取消 |x^$dnsrewrite=127.0.0.1。
func (a *RewriteAction) key() string {
	if a == nil {
		return ""
	}
	if a.Bare {
		return "bare"
	}
	return fmt.Sprintf("%d;%d;%s", a.RCode, a.RRType, normalizeRewriteValue(a.RRType, a.Value))
}

// normalizeRewriteValue 归一化取值以便比较
func normalizeRewriteValue(rrtype uint16, value string) string {
	switch rrtype {
	case dns.TypeA, dns.TypeAAAA:
		if ip := net.ParseIP(strings.TrimSpace(value)); ip != nil {
			return ip.String()
		}
	case dns.TypeCNAME, dns.TypePTR, dns.TypeNS:
		return strings.TrimSuffix(strings.ToLower(strings.TrimSpace(value)), ".")
	}
	return strings.TrimSpace(value)
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
// value 为未经小写化的原文：记录取值与 RCODE 关键字都区分大小写。
// 解析失败返回错误，调用方据此丢弃整条规则（与非法正则的处理一致）。
func parseDNSRewriteModifier(value string) (*RewriteAction, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return &RewriteAction{Bare: true}, nil
	}

	// 显式形式 RCODE;类型;取值。取值本身可能含分号，故只切前两段
	parts := strings.SplitN(trimmed, ";", 3)
	if len(parts) == 1 {
		return parseShorthandRewrite(trimmed)
	}

	rcode, ok := rcodeKeywords[strings.ToUpper(strings.TrimSpace(parts[0]))]
	if !ok {
		return nil, fmt.Errorf("未知的应答码 %q", parts[0])
	}
	if rcode != dns.RcodeSuccess {
		// 非 NOERROR 时类型与取值字段被忽略（规范允许写成 REFUSED;;）
		return &RewriteAction{RCode: rcode}, nil
	}

	typeStr := ""
	if len(parts) > 1 {
		typeStr = strings.TrimSpace(parts[1])
	}
	rawValue := ""
	if len(parts) > 2 {
		rawValue = strings.TrimSpace(parts[2])
	}

	if typeStr == "" {
		// NOERROR;; —— 显式声明该名字无任何记录
		return &RewriteAction{RCode: dns.RcodeSuccess}, nil
	}

	rrtype, ok := dns.StringToType[strings.ToUpper(typeStr)]
	if !ok {
		return nil, fmt.Errorf("未知的记录类型 %q", typeStr)
	}
	if err := validateRewriteValue(rrtype, rawValue); err != nil {
		return nil, err
	}
	return &RewriteAction{RCode: dns.RcodeSuccess, RRType: rrtype, Value: rawValue}, nil
}

// parseShorthandRewrite 解析不带分号的简写取值
func parseShorthandRewrite(value string) (*RewriteAction, error) {
	if rcode, ok := rcodeKeywords[strings.ToUpper(value)]; ok {
		return &RewriteAction{RCode: rcode}, nil
	}

	// 既非应答码也不是地址：按简写规则视作 CNAME 目标
	ip := net.ParseIP(value)
	if ip == nil {
		if err := validateRewriteValue(dns.TypeCNAME, value); err != nil {
			return nil, err
		}
		return &RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeCNAME, Value: value}, nil
	}
	if ip.To4() != nil {
		return &RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeA, Value: value}, nil
	}
	return &RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeAAAA, Value: value}, nil
}

// supportedRewriteRRType 判断记录类型是否有对应的构造实现
func supportedRewriteRRType(rrtype uint16) bool {
	name, ok := dns.TypeToString[rrtype]
	if !ok {
		return false
	}
	_, ok = rewriteRecordTypes[name]
	return ok
}

// validateRewriteValue 校验取值与记录类型是否匹配。
//
// 复用 buildRewriteRR 做实际解析而非另写一套判定：两者若各写一遍，
// 迟早会出现「校验通过但构造失败」这类只在运行时才暴露的偏差。
func validateRewriteValue(rrtype uint16, value string) error {
	typeName := dns.TypeToString[rrtype]
	if !supportedRewriteRRType(rrtype) {
		return fmt.Errorf("记录类型 %s 暂不支持重写", typeName)
	}
	if strings.TrimSpace(value) == "" {
		return fmt.Errorf("%s 记录缺少取值", typeName)
	}

	// 传入 rrtype 作为查询类型，使构造路径不会因类型不匹配而提前返回 nil
	rr, err := buildRewriteRR("probe.invalid.", rrtype, RewriteRecord{Type: typeName, Value: value}, DefaultRewriteTTL)
	if err != nil {
		return err
	}
	if rr == nil {
		return fmt.Errorf("%s 记录的取值 %q 无法解析", typeName, value)
	}
	return nil
}

// isRewriteTarget 判断取值是否为可用的目标域名。
//
// 这里刻意不要求含点：重写目标常是内网单标签主机名（如 nas），
// 与过滤规则模式必须含点的约束无关。
func isRewriteTarget(target string) bool {
	t := strings.TrimSuffix(strings.TrimSpace(target), ".")
	if t == "" || len(t) > 253 || net.ParseIP(t) != nil {
		return false
	}
	for _, label := range strings.Split(t, ".") {
		if label == "" || len(label) > 63 {
			return false
		}
	}
	ascii, err := idna.Lookup.ToASCII(t)
	return err == nil && ascii != ""
}
