package dns

import (
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewSafeBrowsingMiddleware 创建恶意网址库与家长控制拦截中间件。
//
// 借鉴自 AdGuard Home 的 hashprefix 插件：把域名及其各级父域做 SHA-256，
// 取前 2 字节的十六进制拼成查询名发往第三方权威服务器，对方返回命中的
// 完整摘要，本地再比对。第三方只看到 2 字节前缀，无法还原完整域名。
//
// **fail-open**：查询失败（超时、上游故障、解析器未就绪）一律放行，
// 并如实打上失败标记。这与本地黑名单的 fail-closed 相反，是刻意的——
// 本地规则是我们自己掌握的数据，出问题说明配置有误；而声誉查询依赖
// 第三方可用性，让它的抖动决定整个网络的解析成败代价太大。
// 上层可通过标记在日志里观察到这类放行，而不是把它当成一次干净的通过。
func NewSafeBrowsingMiddleware(engine *core.SafeBrowsingEngine, fallback func() core.FilterConfig) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if engine == nil || !engine.IsEnabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		// 只检查会被用于建立连接的记录类型：MX/TXT 等查询本身不产生连接，
		// 拦下来只会让邮件与验证流程莫名失败。
		if !isConnectableQType(q.Qtype) {
			return next()
		}

		domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(q.Name)), ".")
		if domain == "" {
			return next()
		}

		verdict := engine.Check(ctx.Context, domain)

		if verdict.Failed {
			// fail-open：记录失败后照常放行，绝不因为问不到就拦截
			ctx.Set("safebrowsing_failed", true)
			ctx.Set("safebrowsing_service", verdict.Service)
			return next()
		}

		if !verdict.Blocked {
			return next()
		}

		cfg := core.FilterConfig{}
		if fallback != nil {
			cfg = fallback()
		}

		ctx.Resp = BuildBlockedResponse(ctx.Req, cfg)
		ctx.Set("source", "safebrowsing")
		ctx.Set("cache_hit", "safebrowsing")
		ctx.Set("filter_action", "block")
		ctx.Set("filter_blocked", true)
		ctx.Set("filter_rule", domain)
		ctx.Set("filter_reason", verdict.Service)
		ctx.Set("filter_list", verdict.Service)
		return nil
	}
}

// isConnectableQType 判断该查询类型是否会用于建立连接
func isConnectableQType(qtype uint16) bool {
	switch qtype {
	case dns.TypeA, dns.TypeAAAA, dns.TypeHTTPS, dns.TypeSVCB:
		return true
	default:
		return false
	}
}
