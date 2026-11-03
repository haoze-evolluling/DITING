package dns

import (
	"github.com/haoze-evolluling/diting/server/internal/core"
)

// NewClientMiddleware 创建客户端主机名识别与活动记录中间件
// 深度借鉴自 Blocky (client_names_resolver.go) 与 AdGuard Home (internal/rdns)
func NewClientMiddleware(resolver *core.ClientResolver) Middleware {
	return NewClientMiddlewareWithGroups(resolver, nil)
}

// NewClientMiddlewareWithGroups 创建带客户端分组标记的中间件。
//
// 分组标记必须写入在流水线早期：缓存中间件靠它做按组隔离的键，注册晚于缓存会让键退化
// 为默认组，隔离失效。
//
// groups 是取值函数而非实例：分组配置热更新会整体替换解析器，而流水线只在 DNS 启动时
// 装配一次。按值捕获旧实例会让新增分组/成员在转发路径上永久不生效，直到监听器重启。
// 传 nil 表示不启用分组标记。
func NewClientMiddlewareWithGroups(resolver *core.ClientResolver, groups func() *core.GroupResolver) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if resolver != nil && ctx.ClientIP != nil {
			name := resolver.IdentifyClient(ctx.ClientIP)
			ctx.ClientName = name
			if name != "" {
				ctx.Set("client_name", name)
			}
		}

		// 加密入口的 ClientID 优先于反查出来的主机名：前者是客户端自己
		// 声明的身份，设备换 IP 也不会变；后者只是对当前地址的推测。
		if ctx.ClientID != "" {
			ctx.ClientName = ctx.ClientID
			ctx.Set("client_name", ctx.ClientID)
		}

		if groups != nil && ctx.ClientIP != nil {
			if gr := groups(); gr != nil {
				ctx.Set(attrClientGroup, gr.Resolve(ctx.ClientIP))
			}
		}

		return next()
	}
}
