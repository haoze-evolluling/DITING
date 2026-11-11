package dns

import (
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewRateLimitMiddleware 创建客户端请求速率限制洋葱中间件。
// 借鉴自 blocky 与 Pi-hole，抵御恶意客户端的查询泛洪攻击与 DNS 放大攻击，
// 触发限流时返回 REFUSED 并在启用 EDE 时携带 Prohibited 扩展错误码。
func NewRateLimitMiddleware(limiter *core.RateLimiter) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if limiter == nil || !limiter.IsEnabled() || ctx.Req == nil {
			return next()
		}

		if !limiter.Allow(ctx.ClientIP) {
			resp := new(dns.Msg)
			resp.SetRcode(ctx.Req, dns.RcodeRefused)
			resp.RecursionAvailable = true
			ctx.Resp = resp

			ctx.Set("filter_blocked", true)
			ctx.Set("filter_rule", "RATE_LIMIT_EXCEEDED")
			ctx.Set("filter_reason", "Client query rate limit exceeded")
			ctx.Set("ratelimit_blocked", true)
			return nil
		}

		return next()
	}
}
