package dns

import (
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewSafeSearchMiddleware 创建强制安全搜索中间件（默认关闭）。
//
// 借鉴自 AdGuard Home internal/filtering/safesearch：把搜索引擎域名的应答改写为
// 提供商的强制过滤入口（CNAME 或固定 IP），使客户端无法通过设置关闭安全搜索。
//
// 复用 RewriteEngine 的 Lookup 路径派生：仅对 A/AAAA/HTTPS 查询生效，
// 响应阶段就地替换 ctx.Resp，并标注 cache_hit="safesearch" 便于日志区分。
func NewSafeSearchMiddleware(engine *core.SafeSearchEngine) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if engine == nil || !engine.IsEnabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(q.Name)), ".")
		if domain == "" {
			return next()
		}

		res, ok := engine.Lookup(domain, q.Qtype)
		if !ok {
			return next()
		}

		ttl := engine.GetConfig().TTL
		fqdn := dns.Fqdn(q.Name)

		resp := new(dns.Msg)
		resp.SetReply(ctx.Req)
		resp.Authoritative = true
		resp.RecursionAvailable = true
		resp.Rcode = dns.RcodeSuccess

		switch {
		case res.CNAME != "":
			resp.Answer = append(resp.Answer, &dns.CNAME{
				Hdr:    dns.RR_Header{Name: fqdn, Rrtype: dns.TypeCNAME, Class: dns.ClassINET, Ttl: ttl},
				Target: res.CNAME,
			})
		case res.IP != nil && res.IPType == q.Qtype:
			if res.IPType == dns.TypeA {
				resp.Answer = append(resp.Answer, &dns.A{
					Hdr: dns.RR_Header{Name: fqdn, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: ttl},
					A:   res.IP.To4(),
				})
			} else {
				resp.Answer = append(resp.Answer, &dns.AAAA{
					Hdr:  dns.RR_Header{Name: fqdn, Rrtype: dns.TypeAAAA, Class: dns.ClassINET, Ttl: ttl},
					AAAA: res.IP.To16(),
				})
			}
		case res.NODATA:
			// 命中但该查询类型无重写记录，返回权威 NODATA 以阻断外泄
		default:
			return next()
		}

		ctx.Resp = resp
		ctx.Set("source", "safesearch")
		ctx.Set("cache_hit", "safesearch")
		ctx.Set("safesearch_service", res.Service)
		return nil
	}
}
