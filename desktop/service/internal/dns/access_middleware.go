package dns

import (
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewAccessMiddleware 创建客户端访问控制洋葱中间件。
// 借鉴自 AdGuard Home 与 dnscrypt-proxy，拦截未授权或受限制的客户端 IP，
// 遵循标准返回 REFUSED 并在启用 EDE 时注入 RFC 8914 Prohibited 扩展错误码。
func NewAccessMiddleware(ac *core.AccessControl) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if ac == nil || ctx.Req == nil {
			return next()
		}

		allowed, reason := ac.CheckAccess(ctx.ClientIP)
		if !allowed {
			resp := new(dns.Msg)
			resp.SetRcode(ctx.Req, dns.RcodeRefused)
			resp.RecursionAvailable = true
			ctx.Resp = resp

			ctx.Set("filter_blocked", true)
			ctx.Set("filter_rule", "CLIENT_ACCESS_CONTROL")
			ctx.Set("filter_reason", reason)
			ctx.Set("access_blocked", true)
			return nil
		}

		return next()
	}
}
