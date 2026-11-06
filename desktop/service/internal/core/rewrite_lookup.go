package core

import (
	"log"
	"net"
	"strings"

	"github.com/miekg/dns"
)

// Lookup 查找匹配的重写规则。
//
// 返回 matched=true 表示该域名已被重写规则捕获，此时即使 answers 为空
// 也必须以权威 NODATA 应答，否则该名字会外泄到上游。
//
// rcode 覆盖仅影响应答码，不影响是否命中：需要把域名整体置为不存在时，
// 命中本身仍然成立（否则会退回普通解析，与用户意图相反）。
func (e *RewriteEngine) Lookup(domain string, qtype uint16) (answers []dns.RR, matched bool) {
	answers, _, matched = e.LookupDetailed(domain, qtype)
	return answers, matched
}

// LookupDetailed 与 Lookup 相同，但额外返回应答码覆盖（未覆盖时为 RcodeSuccess）
func (e *RewriteEngine) LookupDetailed(domain string, qtype uint16) (answers []dns.RR, rcode int, matched bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if e.native == nil {
		return nil, dns.RcodeSuccess, false
	}
	answers, rcode, matched, err := e.native.lookup(domain, qtype)
	if err != nil {
		// 句柄构建成功之后单次查询不应失败（只有 ABI 错配才会走到这里）。
		// 放行到下一个中间件比让解析器崩掉安全。
		log.Printf("[Rewrite] 判定内核失败: %v\n", err)
		return nil, dns.RcodeSuccess, false
	}
	return answers, rcode, matched
}

// LookupPTR 根据 IP 反向解析域名（O(1) 精确反查，支持多域名别名）
func (e *RewriteEngine) LookupPTR(ptrQuery string) (answers []dns.RR, matched bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if e.native == nil {
		return nil, false
	}
	ip := ParseIPFromArpa(ptrQuery)
	if ip == nil {
		return nil, false
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}

	domains, err := e.native.lookupPTR(ip)
	if err != nil {
		log.Printf("[Rewrite] PTR 内核失败: %v\n", err)
		return nil, false
	}
	if len(domains) == 0 {
		return nil, false
	}

	fqdn := dns.Fqdn(ptrQuery)
	answers = make([]dns.RR, 0, len(domains))
	for _, domain := range domains {
		answers = append(answers, &dns.PTR{
			Hdr: dns.RR_Header{Name: fqdn, Rrtype: dns.TypePTR, Class: dns.ClassINET, Ttl: e.defaultTTL},
			Ptr: domain,
		})
	}
	return answers, true
}

// LookupReverse 实现 ReverseLookuper 接口，根据 IP 反向查询重写匹配的域名
func (e *RewriteEngine) LookupReverse(ip net.IP) string {
	if ip == nil {
		return ""
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}

	e.mu.RLock()
	defer e.mu.RUnlock()
	if e.native == nil {
		return ""
	}
	domain, err := e.native.lookupReverse(ip)
	if err != nil {
		log.Printf("[Rewrite] 反向查询内核失败: %v\n", err)
		return ""
	}
	return strings.TrimSuffix(domain, ".")
}
