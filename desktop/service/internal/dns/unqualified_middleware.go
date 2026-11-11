package dns

import (
	"strings"

	"github.com/miekg/dns"
)

// NewDynamicUnqualifiedMiddleware 创建支持动态状态判定的拦截无点单标签不完整域名外泄洋葱中间件。
func NewDynamicUnqualifiedMiddleware(enabled func() bool) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if enabled == nil || !enabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		clean := strings.TrimSuffix(q.Name, ".")

		// 单标签域名（如 "printer", "wpad", "nas" 等且不包含点号）
		if clean != "" && !strings.Contains(clean, ".") {
			resp := new(dns.Msg)
			resp.SetRcode(ctx.Req, dns.RcodeNameError)
			resp.Authoritative = true
			resp.RecursionAvailable = true
			ctx.Resp = resp

			ctx.Set("filter_blocked", true)
			ctx.Set("filter_rule", "BLOCK_UNQUALIFIED")
			ctx.Set("filter_reason", "Unqualified domain name leak blocked")
			ctx.Set("unqualified_blocked", true)
			return nil
		}

		return next()
	}
}

// NewUnqualifiedMiddleware 创建拦截无点单标签不完整域名（Unqualified / Non-FQDN）外泄的洋葱中间件。
// 借鉴自 blocky (fqdn_only_resolver.go) 与 dnscrypt-proxy (plugin_block_unqualified.go)。
// 放在 Hosts 中间件之后：若本地 Hosts 未定义该局域网主机名，则阻断其泄露至公网，
// 权威返回 NXDOMAIN 并在启用 EDE 时附带 Blocked 扩展错误码。
func NewUnqualifiedMiddleware(enabled bool) Middleware {
	return NewDynamicUnqualifiedMiddleware(func() bool { return enabled })
}
