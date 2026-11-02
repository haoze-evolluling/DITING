package dns

import (
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewZoneMiddleware 创建本地权威区（zone 文件）解析中间件。
//
// 借鉴自 AdGuard Home (dnsforward/zone.go) 与 blocky (custom_dns_resolver)：
// 与 hosts / rewrite 的区别在于「权威范围」——区顶点及其以下的所有名字都
// 由本地负责，区里没有的名字返回权威 NODATA 而不是继续向上游查询。
//
// 正因如此它必须排在 hosts 之前：用户显式声明的区，其语义比系统 hosts
// 文件里偶然存在的同名条目更明确。
func NewZoneMiddleware(engine *core.ZoneEngine) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if engine == nil || !engine.IsEnabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		if strings.TrimSpace(q.Name) == "" {
			return next()
		}

		answers, soa, matched := engine.Lookup(q.Name, q.Qtype)
		if !matched {
			return next()
		}

		resp := new(dns.Msg)
		resp.SetReply(ctx.Req)
		resp.Authoritative = true
		resp.RecursionAvailable = true
		resp.Rcode = dns.RcodeSuccess
		resp.Answer = answers

		ctx.Resp = resp
		ctx.Set("source", "zone")
		if len(answers) == 0 {
			// 权威 NODATA：附上所属区的 SOA，客户端才能按 RFC 2308 负缓存，
			// 否则每次查询都要重新走一遍本地解析
			if soa != nil {
				resp.Ns = append(resp.Ns, soa)
			}
			ctx.Set("cache_hit", "zone_nodata")
		} else {
			ctx.Set("cache_hit", "zone")
		}
		return nil
	}
}
