package dns

import (
	"net"
	"strings"

	"github.com/miekg/dns"
)

// NewSUDNMiddleware 创建处理 RFC 6761、RFC 7686、RFC 9462 特殊用途域名 (Special-Use Domain Names) 的快速拦截中间件。
// 借鉴自 blocky (sudn_resolver.go) 与 AdGuard Home，杜绝将 localhost、.onion、.invalid、DDR 探测泄漏给公网上游。
func NewSUDNMiddleware() Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		name := strings.ToLower(strings.Trim(q.Name, "."))
		if name == "" {
			return next()
		}

		// 1. localhost (RFC 6761 §6.3) 本地回环直接权威应答
		if name == "localhost" || strings.HasSuffix(name, ".localhost") {
			resp := new(dns.Msg)
			resp.SetReply(ctx.Req)
			resp.Authoritative = true
			resp.RecursionAvailable = true
			resp.Rcode = dns.RcodeSuccess

			switch q.Qtype {
			case dns.TypeA:
				resp.Answer = append(resp.Answer, &dns.A{
					Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300},
					A:   net.ParseIP("127.0.0.1"),
				})
			case dns.TypeAAAA:
				resp.Answer = append(resp.Answer, &dns.AAAA{
					Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: 300},
					AAAA: net.IPv6loopback,
				})
			}
			ctx.Resp = resp
			ctx.Set("sudn_handled", true)
			ctx.Set("source", "sudn")
			return nil
		}

		// 2. test, invalid (RFC 6761 §6.2, §6.4), onion (RFC 7686) 与 home.arpa (RFC 8375 §4) 返回 NXDOMAIN
		if name == "test" || strings.HasSuffix(name, ".test") ||
			name == "invalid" || strings.HasSuffix(name, ".invalid") ||
			name == "onion" || strings.HasSuffix(name, ".onion") ||
			name == "home.arpa" || strings.HasSuffix(name, ".home.arpa") {
			resp := new(dns.Msg)
			resp.SetReply(ctx.Req)
			resp.Authoritative = true
			resp.RecursionAvailable = true
			resp.Rcode = dns.RcodeNameError
			ctx.Resp = resp
			ctx.Set("sudn_handled", true)
			ctx.Set("source", "sudn")
			return nil
		}

		// 3. RFC 9462 DDR 防绕过探测 (resolver.arpa / _dns.resolver.arpa)
		// 权威静默返回 NODATA，杜绝下游操作系统绕过本地代理并向上游泄漏
		if name == "resolver.arpa" || strings.HasSuffix(name, ".resolver.arpa") {
			resp := new(dns.Msg)
			resp.SetReply(ctx.Req)
			resp.Authoritative = true
			resp.RecursionAvailable = true
			resp.Rcode = dns.RcodeSuccess
			ctx.Resp = resp
			ctx.Set("sudn_handled", true)
			ctx.Set("source", "sudn_ddr")
			return nil
		}

		return next()
	}
}
