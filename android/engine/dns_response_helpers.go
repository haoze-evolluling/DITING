// dns_response_helpers.go holds DNS answer inspection shared by the standalone server and the
// full-tunnel DNS-over-gVisor handlers, plus the resolved-address bookkeeping the engine keeps.
//
// The verdict ("every A/AAAA answer is a null block or loopback") and the logged address list are
// computed by rust/diting-dns-core: the Go side only walks the dns.Msg into the payload, because
// the records themselves are Go values it also needs for the cache and the response chain.

package tunnel

import (
	"net"
	"strings"

	"github.com/miekg/dns"
)

// inspectUpstreamAnswer asks the kernel two questions about one upstream answer: is it a null
// block, and which address texts do we log (unique, in answer order, comma separated).
//
// Both entry points must agree on this; the standalone server logs the addresses, the diagnostics
// path only needs the verdict, so one call serves both.
func inspectUpstreamAnswer(msg *dns.Msg) (blocked bool, addresses string) {
	if msg == nil || len(msg.Answer) == 0 {
		return false, ""
	}
	blocked, addresses, err := inspectNativeAnswer(encodeAnswerRequest(msg))
	if err != nil {
		// A missing kernel already logged once at load; a rejected payload is a real bug worth a
		// line. Either way the answer is treated as normal, which is the safe direction for a
		// filtering verdict.
		if dnsCoreAvailable() {
			logf("dnsAnswer: inspection failed, treating the answer as normal: %v", err)
		}
		return false, ""
	}
	return blocked, addresses
}

// isUpstreamBlockedMsg reports whether every A/AAAA answer is a null block or loopback: upstreams
// that block a domain answer `0.0.0.0` / `::` instead of an error code.
func isUpstreamBlockedMsg(msg *dns.Msg) bool {
	blocked, _ := inspectUpstreamAnswer(msg)
	return blocked
}

func rewriteAnswerRecord(q dns.Question, ip net.IP) dns.RR {
	if q.Qtype == dns.TypeAAAA {
		return &dns.AAAA{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: rewriteAnswerTTL}, AAAA: ip}
	}
	return &dns.A{Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: rewriteAnswerTTL}, A: ip.To4()}
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
