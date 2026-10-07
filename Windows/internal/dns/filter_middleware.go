package dns

import (
	"net"
	"strings"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/miekg/dns"
)

// NewFilterMiddleware 创建规则过滤与拦截流水线中间件
func NewFilterMiddleware(engine *core.RuleEngine) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if engine == nil || !engine.IsEnabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(q.Name)), ".")
		if domain == "" {
			return next()
		}

		res := engine.Match(domain, q.Qtype)

		if res.Blocked {
			// 构建阻断响应报文并短路返回
			resp := buildBlockedResponse(ctx.Req, engine.GetConfig())
			ctx.Resp = resp
			ctx.Set("filter_action", "block")
			ctx.Set("filter_blocked", true)
			ctx.Set("filter_rule", res.MatchedRule)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_list", res.ListName)
			return nil
		}

		if res.Action == "allow" {
			ctx.Set("filter_action", "allow")
			ctx.Set("filter_blocked", false)
			ctx.Set("filter_rule", res.MatchedRule)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_list", res.ListName)
		}

		return next()
	}
}

// buildBlockedResponse 依据配置策略组装阻断 DNS 应答报文
func buildBlockedResponse(req *dns.Msg, cfg core.FilterConfig) *dns.Msg {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Authoritative = true
	resp.RecursionAvailable = true

	q := req.Question[0]

	switch cfg.BlockMode {
	case core.BlockModeNXDOMAIN:
		resp.Rcode = dns.RcodeNameError
		return resp

	case core.BlockModeRefused:
		resp.Rcode = dns.RcodeRefused
		return resp

	case core.BlockModeNullIP:
		fallthrough
	default:
		resp.Rcode = dns.RcodeSuccess

		switch q.Qtype {
		case dns.TypeA:
			ip := net.ParseIP(cfg.BlockingIPv4)
			if ip == nil {
				ip = net.IPv4zero
			}
			ip = ip.To4()
			if ip != nil {
				rr := &dns.A{
					Hdr: dns.RR_Header{
						Name:   q.Name,
						Rrtype: dns.TypeA,
						Class:  dns.ClassINET,
						Ttl:    core.DefaultRuleTTL,
					},
					A: ip,
				}
				resp.Answer = append(resp.Answer, rr)
			}

		case dns.TypeAAAA:
			ip := net.ParseIP(cfg.BlockingIPv6)
			if ip == nil {
				ip = net.IPv6zero
			}
			rr := &dns.AAAA{
				Hdr: dns.RR_Header{
					Name:   q.Name,
					Rrtype: dns.TypeAAAA,
					Class:  dns.ClassINET,
					Ttl:    core.DefaultRuleTTL,
				},
				AAAA: ip,
			}
			resp.Answer = append(resp.Answer, rr)

		default:
			// 对于 MX/TXT 等非常规类型，保持 NOERROR 且 Answer 留空 (NODATA)
		}

		return resp
	}
}
