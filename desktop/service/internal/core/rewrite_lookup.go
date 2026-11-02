package core

import (
	"net"
	"strings"

	"github.com/miekg/dns"
)

func (e *RewriteEngine) chaseCNAME(targetFQDN string, qtype uint16, visited map[string]bool) []dns.RR {
	if len(visited) > 8 {
		return nil
	}
	targetNorm := normalizeRewriteDomain(targetFQDN)
	if targetNorm == "" || visited[targetNorm] {
		return nil
	}
	visited[targetNorm] = true

	rule, ok := e.findRule(targetNorm)
	if !ok {
		return nil
	}

	var chained []dns.RR
	switch qtype {
	case dns.TypeA:
		if len(rule.v4List) > 0 {
			for _, ip := range rule.v4List {
				chained = append(chained, &dns.A{
					Hdr: dns.RR_Header{Name: dns.Fqdn(targetFQDN), Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: rule.ttl},
					A:   ip,
				})
			}
		} else if rule.cname != "" {
			chained = append(chained, &dns.CNAME{
				Hdr:    dns.RR_Header{Name: dns.Fqdn(targetFQDN), Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: rule.ttl},
				Target: rule.cname,
			})
			chained = append(chained, e.chaseCNAME(rule.cname, qtype, visited)...)
		}
	case dns.TypeAAAA:
		if len(rule.v6List) > 0 {
			for _, ip := range rule.v6List {
				chained = append(chained, &dns.AAAA{
					Hdr:  dns.RR_Header{Name: dns.Fqdn(targetFQDN), Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: rule.ttl},
					AAAA: ip,
				})
			}
		} else if rule.cname != "" {
			chained = append(chained, &dns.CNAME{
				Hdr:    dns.RR_Header{Name: dns.Fqdn(targetFQDN), Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: rule.ttl},
				Target: rule.cname,
			})
			chained = append(chained, e.chaseCNAME(rule.cname, qtype, visited)...)
		}
	}
	return chained
}

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

	if !e.enabled {
		return nil, dns.RcodeSuccess, false
	}

	norm := normalizeRewriteDomain(domain)
	if norm == "" {
		return nil, dns.RcodeSuccess, false
	}

	cr, ok := e.findRule(norm)
	if !ok {
		return nil, dns.RcodeSuccess, false
	}

	// 匹配成功，标记为已被重写规则捕获
	matched = true
	rcode = cr.rcode
	fqdn := domain
	if !strings.HasSuffix(fqdn, ".") {
		fqdn += "."
	}

	// 非 NOERROR 的重写不产出记录：客户端只应看到失败结论
	if rcode != dns.RcodeSuccess {
		return nil, rcode, true
	}

	answers = append(answers, e.matchShortcutRecords(cr, fqdn, norm, qtype)...)
	answers = append(answers, e.matchExplicitRecords(cr, fqdn, qtype)...)
	return mergeOwnerCNAME(answers), rcode, true
}

// mergeOwnerCNAME 保证同一属主名的 CNAME 与其他记录互斥（RFC 1034 §3.6.2）。
//
// 快捷字段与 Records 是两份可并存的配置，旧实现直接串接二者的结果，
// 同一规则里同时写了 CNAME 与 A 就会返回 [CNAME, A]。存在 CNAME 时
// 只保留 CNAME 链：它才定义了该名字的解析语义，同时给出其他类型会让
// 严格的 stub 校验器整包丢弃、宽松的实现则各取所需。
func mergeOwnerCNAME(answers []dns.RR) []dns.RR {
	// 按属主名建索引：链式解析里后续的 A 记录属于另一个属主名，必须保留
	owners := make(map[string]bool)
	for _, rr := range answers {
		if rr.Header().Rrtype == dns.TypeCNAME {
			owners[strings.ToLower(rr.Header().Name)] = true
		}
	}
	if len(owners) == 0 {
		return answers
	}
	out := make([]dns.RR, 0, len(answers))
	for _, rr := range answers {
		hdr := rr.Header()
		if owners[strings.ToLower(hdr.Name)] && hdr.Rrtype != dns.TypeCNAME {
			continue
		}
		out = append(out, rr)
	}
	return out
}

// matchShortcutRecords 处理 IPs / CNAME / TXT 三个快捷字段
func (e *RewriteEngine) matchShortcutRecords(cr *compiledRule, fqdn, norm string, qtype uint16) []dns.RR {
	var answers []dns.RR

	switch qtype {
	case dns.TypeA:
		if len(cr.v4List) > 0 {
			for _, ip := range cr.v4List {
				answers = append(answers, &dns.A{
					Hdr: dns.RR_Header{Name: fqdn, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: cr.ttl},
					A:   ip,
				})
			}
		} else if cr.cname != "" {
			answers = append(answers, e.buildCNAME(cr, fqdn))
			answers = append(answers, e.chaseCNAME(cr.cname, dns.TypeA, map[string]bool{norm: true})...)
		}
	case dns.TypeAAAA:
		if len(cr.v6List) > 0 {
			for _, ip := range cr.v6List {
				answers = append(answers, &dns.AAAA{
					Hdr:  dns.RR_Header{Name: fqdn, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: cr.ttl},
					AAAA: ip,
				})
			}
		} else if cr.cname != "" {
			answers = append(answers, e.buildCNAME(cr, fqdn))
			answers = append(answers, e.chaseCNAME(cr.cname, dns.TypeAAAA, map[string]bool{norm: true})...)
		}
	case dns.TypeCNAME:
		if cr.cname != "" {
			answers = append(answers, e.buildCNAME(cr, fqdn))
		}
	case dns.TypeTXT:
		if len(cr.txt) > 0 {
			answers = append(answers, &dns.TXT{
				Hdr: dns.RR_Header{Name: fqdn, Rrtype: dns.TypeTXT, Class: dns.ClassINET, Ttl: cr.ttl},
				Txt: cr.txt,
			})
		}
	}

	return answers
}

// matchExplicitRecords 处理 Records 中的显式记录。
//
// 取值非法的记录在编译阶段已被剔除，这里遇到只可能是零值占位，
// 因此静默跳过而不是让整条规则失效。
func (e *RewriteEngine) matchExplicitRecords(cr *compiledRule, fqdn string, qtype uint16) []dns.RR {
	if len(cr.records) == 0 {
		return nil
	}

	var answers []dns.RR
	for _, rec := range cr.records {
		rr, err := buildRewriteRR(fqdn, qtype, rec, cr.ttl)
		if err != nil || rr == nil {
			continue
		}
		answers = append(answers, rr)
	}
	return answers
}

// buildCNAME 构造快捷字段对应的 CNAME 记录
func (e *RewriteEngine) buildCNAME(cr *compiledRule, fqdn string) dns.RR {
	return &dns.CNAME{
		Hdr:    dns.RR_Header{Name: fqdn, Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: cr.ttl},
		Target: cr.cname,
	}
}

// LookupPTR 根据 IP 反向解析域名（O(1) 精确反查，支持多域名别名）
func (e *RewriteEngine) LookupPTR(ptrQuery string) (answers []dns.RR, matched bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if !e.enabled {
		return nil, false
	}

	ip := ParseIPFromArpa(ptrQuery)
	if ip == nil {
		return nil, false
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}

	domains, ok := e.ptrMap[ip.String()]
	if !ok || len(domains) == 0 {
		return nil, false
	}

	fqdn := dns.Fqdn(ptrQuery)
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
	if !e.enabled {
		return ""
	}
	if domains, ok := e.ptrMap[ip.String()]; ok && len(domains) > 0 {
		return strings.TrimSuffix(domains[0], ".")
	}
	return ""
}
