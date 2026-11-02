package dns

import (
	"fmt"

	"github.com/miekg/dns"
)

// NewEDEMiddleware 创建遵循 RFC 8914 规范的 Extended DNS Errors (EDE) 响应增强中间件。
// 借鉴自 blocky (ede_resolver.go) 与 AdGuard Home，为客户端提供详尽的标准 DNS 错误与拦截原因。
// 支持传入静态 bool 或动态 func() bool 查询函数以支持配置热重载。
func NewEDEMiddleware(enabled any) Middleware {
	var isEnabled func() bool
	switch v := enabled.(type) {
	case func() bool:
		isEnabled = v
	case bool:
		isEnabled = func() bool { return v }
	default:
		isEnabled = func() bool { return true }
	}

	return func(ctx *DNSContext, next func() error) error {
		err := next()
		// RFC 8914 Section 3: 响应中不得包含 EDE 选项，除非客户端查询本身携带了 OPT pseudo-RR (EDNS0)
		if !isEnabled() || ctx.Resp == nil || ctx.Req == nil || ctx.Req.IsEdns0() == nil {
			return err
		}

		// 1. 客户端访问控制拦截 (ACL Prohibited)
		if val, ok := ctx.Get("access_blocked"); ok && val == true {
			reason := "DITING: Client query prohibited by access policy"
			if rVal, ok := ctx.Get("filter_reason"); ok {
				if rStr, ok := rVal.(string); ok && rStr != "" {
					reason = fmt.Sprintf("DITING: %s", rStr)
				}
			}
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeProhibited, reason)
			return err
		}

		// 2. 客户端请求速率限制拦截 (Rate Limit Prohibited)
		if val, ok := ctx.Get("ratelimit_blocked"); ok && val == true {
			reason := "DITING: Client query rate limit exceeded"
			if rVal, ok := ctx.Get("filter_reason"); ok {
				if rStr, ok := rVal.(string); ok && rStr != "" {
					reason = fmt.Sprintf("DITING: %s", rStr)
				}
			}
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeProhibited, reason)
			return err
		}

		// 3. DNS Rebinding 防御拦截
		if val, ok := ctx.Get("rebinding_blocked"); ok && val == true {
			reason := "DITING: Blocked by DNS rebinding protection"
			if rVal, ok := ctx.Get("filter_reason"); ok {
				if rStr, ok := rVal.(string); ok && rStr != "" {
					reason = fmt.Sprintf("DITING: %s", rStr)
				}
			}
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeProhibited, reason)
			return err
		}

		// 4. 单标签不完整域名外泄阻断 (Unqualified Blocked)
		if val, ok := ctx.Get("unqualified_blocked"); ok && val == true {
			reason := "DITING: Blocked unqualified domain leak"
			if rVal, ok := ctx.Get("filter_reason"); ok {
				if rStr, ok := rVal.(string); ok && rStr != "" {
					reason = fmt.Sprintf("DITING: %s", rStr)
				}
			}
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeBlocked, reason)
			return err
		}

		// 5. ANY 查询最小化（RFC 8482）
		if val, ok := ctx.Get("any_blocked"); ok && val == true {
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeBlocked, "DITING: ANY 查询已按 RFC 8482 最小化应答")
			return err
		}

		// 6. 伪应答纠正（上游劫持）
		//
		// 标为被拦截（Blocked）而非伪造应答（Forged Answer）：
		// 纠正后的报文是 NXDOMAIN，并未替客户端"伪造"任何地址。
		if val, ok := ctx.Get("bogus_nxdomain"); ok && val == true {
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeBlocked, "DITING: 上游返回劫持地址，已纠正为 NXDOMAIN")
			return err
		}

		// 7. 规则过滤拦截 (AdGuard / 黑名单)
		if val, ok := ctx.Get("filter_blocked"); ok && val == true {
			reason := "DITING: Blocked by filter rule"
			if rVal, ok := ctx.Get("filter_reason"); ok {
				if rStr, ok := rVal.(string); ok && rStr != "" {
					reason = fmt.Sprintf("DITING: %s", rStr)
				}
			}
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeBlocked, reason)
			return err
		}

		// 8. 上游解析故障 (SERVFAIL / Network Error)
		if ctx.Err != nil || ctx.Resp.Rcode == dns.RcodeServerFailure {
			errMsg := "DITING: Upstream resolution failed"
			if ctx.Err != nil {
				errMsg = fmt.Sprintf("DITING: %v", ctx.Err)
			}
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeNetworkError, errMsg)
			return err
		}

		// 9. 过期容灾缓存 (Stale-While-Revalidate)
		if val, ok := ctx.Get("cache_hit"); ok && val == "stale" {
			SetEDE(ctx.Resp, dns.ExtendedErrorCodeCachedError, "DITING: Stale cache response (network degraded)")
			return err
		}

		return err
	}
}
