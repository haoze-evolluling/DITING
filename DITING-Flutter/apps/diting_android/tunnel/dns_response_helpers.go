// dns_response_helpers.go holds DNS answer inspection helpers shared by the
// standalone server and the full-tunnel DNS-over-gVisor handlers.

package tunnel

import (
	"net"
	"strings"

	"github.com/miekg/dns"
)

func rewriteAnswerRecord(q dns.Question, ip net.IP) dns.RR {
	if q.Qtype == dns.TypeAAAA {
		return &dns.AAAA{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: rewriteAnswerTTL}, AAAA: ip}
	}
	return &dns.A{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: rewriteAnswerTTL}, A: ip.To4()}
}

func isUpstreamBlockedMsg(msg *dns.Msg) bool {
	if msg == nil || len(msg.Answer) == 0 {
		return false
	}

	nullCount := 0
	ipRecordCount := 0

	for _, rr := range msg.Answer {
		switch r := rr.(type) {
		case *dns.A:
			ipRecordCount++
			if r.A.Equal(net.IPv4zero) || r.A.IsLoopback() {
				nullCount++
			}
		case *dns.AAAA:
			ipRecordCount++
			if r.AAAA.Equal(net.IPv6zero) || r.AAAA.IsLoopback() {
				nullCount++
			}
		}
	}

	return ipRecordCount > 0 && nullCount == ipRecordCount
}

func resolvedAddressesMsg(response *dns.Msg) string {
	if response == nil {
		return ""
	}
	seen := make(map[string]struct{})
	addresses := make([]string, 0, len(response.Answer))
	for _, answer := range response.Answer {
		var address string
		switch record := answer.(type) {
		case *dns.A:
			address = record.A.String()
		case *dns.AAAA:
			address = record.AAAA.String()
		}
		if address == "" {
			continue
		}
		if _, exists := seen[address]; exists {
			continue
		}
		seen[address] = struct{}{}
		addresses = append(addresses, address)
	}
	return strings.Join(addresses, ",")
}

func (e *Engine) rememberResolvedIPs(domain string, respMsg *dns.Msg) {
	if e == nil || e.ipDomainCache == nil || respMsg == nil || len(respMsg.Answer) == 0 {
		return
	}
	cleanDomain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if cleanDomain == "" {
		return
	}
	for _, ans := range respMsg.Answer {
		switch rr := ans.(type) {
		case *dns.A:
			if rr.A != nil && !rr.A.IsUnspecified() && !rr.A.IsLoopback() {
				e.ipDomainCache.put(rr.A.String(), cleanDomain)
			}
		case *dns.AAAA:
			if rr.AAAA != nil && !rr.AAAA.IsUnspecified() && !rr.AAAA.IsLoopback() {
				e.ipDomainCache.put(rr.AAAA.String(), cleanDomain)
			}
		}
	}
}

func (e *Engine) rememberResolvedIPList(domain string, ipList []string) {
	if e == nil || e.ipDomainCache == nil || len(ipList) == 0 {
		return
	}
	cleanDomain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if cleanDomain == "" {
		return
	}
	for _, ip := range ipList {
		if ip != "" && ip != "0.0.0.0" && ip != "::" && ip != "127.0.0.1" {
			e.ipDomainCache.put(ip, cleanDomain)
		}
	}
}
