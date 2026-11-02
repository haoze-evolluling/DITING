package dns

// NewECHMiddleware 创建 Encrypted Client Hello (ECH) 参数剥离中间件
// 深度借鉴自 AdGuard Home 与 RFC 9460 §6.3，防止客户端利用 ECH 绕过局域网安全策略与审计
func NewECHMiddleware(enabledFunc func() bool) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		err := next()
		if err != nil {
			return err
		}

		isEnabled := false
		if enabledFunc != nil {
			isEnabled = enabledFunc()
		}
		if !isEnabled || ctx.Resp == nil {
			return nil
		}

		if StripECH(ctx.Resp) {
			ctx.Set("ech_stripped", true)
		}
		return nil
	}
}
