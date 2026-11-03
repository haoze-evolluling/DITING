package dns

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// GroupUpstreamResolver 提供按客户端分组取答案的能力。
//
// 抽成接口而非直接依赖 *core.CoreResolver，便于单测注入桩，
// 也让本中间件不必关心上游的调度与连接细节。
type GroupUpstreamResolver interface {
	// HasGroupUpstreams 判断该分组是否配置了专属上游
	HasGroupUpstreams(group string) bool
	// ExchangeForGroup 使用该分组的专属上游解析请求
	ExchangeForGroup(ctx context.Context, group string, req *dns.Msg) (*dns.Msg, error)
}

// NewUpstreamRouteMiddleware 创建按客户端分组短路取答的中间件。
//
// 分组配了专属上游就直接取答并短路，否则原样放行，行为与不注册本中间件完全一致。
// 注册在 cacheMw 之后、forwardMw 之前：晚于缓存可复用其隔离键，早于转发才能先于默认上游接管。
//
// resolver 或 groups 为 nil 时永远是空操作；groups 是取值函数（热更新会替换解析器实例，
// 流水线只装配一次）。
func NewUpstreamRouteMiddleware(resolver GroupUpstreamResolver, groups func() *core.GroupResolver) Middleware {
	if groups == nil {
		return func(ctx *DNSContext, next func() error) error { return next() }
	}
	return func(ctx *DNSContext, next func() error) error {
		if resolver == nil || groups() == nil || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		group := cachedGroup(ctx)
		if group == core.DefaultClientGroupID || !resolver.HasGroupUpstreams(group) {
			return next()
		}

		resp, err := resolver.ExchangeForGroup(ctx.Context, group, ctx.Req)
		if err != nil || resp == nil {
			// 专属上游失败时回落默认链路。
			// 这里刻意不把错误向上抛出：分组专属上游是"优选解析路径"而非唯一路径，
			// 让它的故障直接演变成解析失败对用户没有收益。
			return next()
		}

		resp.Id = ctx.Req.Id
		ctx.Resp = resp
		ctx.Set("upstream_route", group)
		return nil
	}
}
