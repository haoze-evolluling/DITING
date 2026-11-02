package dns

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewCacheMiddleware 创建智能缓存流水线中间件（不区分客户端分组）
func NewCacheMiddleware(cache *core.DNSCache, resolver core.Resolver) Middleware {
	return NewCacheMiddlewareWithGroups(cache, resolver, nil)
}

// NewCacheMiddlewareWithGroups 创建带客户端分组隔离的缓存中间件。
//
// groups 为取值函数（分组热更新会替换解析器实例，流水线只装配一次）；
// 为 nil 时键退回默认组，行为与既有版本逐字一致。
// 非 nil 时按分组隔离：不同分组可能被路由到不同上游、得到不同应答，
// 共用缓存会让 A 组的结果被 B 组命中，分组的策略隔离随之失效。
//
// 注：分组判定本身由 client 中间件写入上下文，这里只消费上下文属性，
// 参数保留是为了让调用方签名统一、并可在装配期做 nil 判定。
func NewCacheMiddlewareWithGroups(cache *core.DNSCache, resolver core.Resolver, groups func() *core.GroupResolver) Middleware {
	_ = groups
	return func(ctx *DNSContext, next func() error) error {
		if cache == nil || !cache.IsEnabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		req := ctx.Req
		q := req.Question[0]

		// 命中排除规则的域名完全绕过缓存：既不读也不写。
		// 只跳过读取会让被排除的应答仍占用容量并可能被他人命中；
		// 只跳过写入则等于"永不命中"，两处都要拦。
		if cache.IsExcluded(q.Name) {
			return next()
		}

		group := cachedGroup(ctx)
		cachedResp, hit, isStale, staleCandidate := cache.GetForGroup(req, group)

		// 1. 有效期内新鲜命中 (Fresh Hit)
		if hit && cachedResp != nil {
			ctx.Resp = cachedResp
			ctx.Set("cache_hit", "fresh")
			return nil
		}

		// 2. 过期宽限期内的陈旧条目 (Optimistic Stale-While-Revalidate 容灾)
		if isStale && staleCandidate != nil && cache.IsStaleFallbackEnabled() {
			if cache.IsOptimistic() {
				staleResp := cache.BuildStaleResponse(req, staleCandidate)
				if staleResp != nil {
					ctx.Resp = staleResp
					ctx.Set("cache_hit", "stale")

					// 后台异步回源刷新 (并发单飞防惊群)
					if resolver != nil {
						reqCopy := req.Copy()
						go func() {
							flightKey := core.CacheKeyForGroup(q.Name, q.Qtype, q.Qclass, group)
							_, _, _ = cache.SingleFlight(flightKey, func() (*dns.Msg, error) {
								freshResp, err := resolver.Exchange(context.Background(), reqCopy)
								if err == nil && freshResp != nil {
									cache.PutForGroup(reqCopy, freshResp, group)
								}
								return freshResp, err
							})
						}()
					}
					return nil
				}
			}
		}

		// 3. 缓存未命中 (Cache Miss)，调用下层中间件 (ForwardMiddleware)
		// 结合 singleflight 防并发回源击穿
		flightKey := core.CacheKeyForGroup(q.Name, q.Qtype, q.Qclass, group)
		var innerErr error

		val, shared, flightErr := cache.SingleFlight(flightKey, func() (*dns.Msg, error) {
			innerErr = next()
			if innerErr == nil && ctx.Resp != nil {
				cache.PutForGroup(req, ctx.Resp, group)
				return ctx.Resp, nil
			}
			return ctx.Resp, innerErr
		})

		// 若为并发共享等待者，优先使用最新写入的缓存以具备动态 TTL 重写；
		// 若条目未入缓存（如 TTL=0 或未开启负缓存），则回退使用 SingleFlight 交付的响应副本
		if shared {
			if freshResp, hit, _, _ := cache.GetForGroup(req, group); hit && freshResp != nil {
				ctx.Resp = freshResp
				ctx.Set("cache_hit", "fresh")
				ctx.Err = nil
				return nil
			}
			if val != nil {
				ctx.Resp = val.Copy()
				ctx.Resp.Id = req.Id
			}
			if flightErr != nil || ctx.Resp == nil || ctx.Resp.Rcode == dns.RcodeServerFailure {
				if isStale && staleCandidate != nil && cache.IsStaleFallbackEnabled() {
					staleResp := cache.BuildStaleResponse(req, staleCandidate)
					if staleResp != nil {
						ctx.Resp = staleResp
						ctx.Set("cache_hit", "stale_fallback")
						ctx.Err = nil
						return nil
					}
				}
				ctx.Err = flightErr
				return flightErr
			}
			ctx.Err = nil
			return nil
		}

		// 4. 回源发生错误或 SERVFAIL，检查是否存在可用 Stale 候选进行降级容灾
		if innerErr != nil || flightErr != nil || ctx.Resp == nil || ctx.Resp.Rcode == dns.RcodeServerFailure {
			if isStale && staleCandidate != nil && cache.IsStaleFallbackEnabled() {
				staleResp := cache.BuildStaleResponse(req, staleCandidate)
				if staleResp != nil {
					ctx.Resp = staleResp
					ctx.Set("cache_hit", "stale_fallback")
					ctx.Err = nil
					return nil
				}
			}
			if innerErr != nil {
				return innerErr
			}
			return flightErr
		}

		return nil
	}
}

// cachedGroup 取出该查询的客户端分组；未启用分组时返回默认组。
//
// 分组由 client 中间件在流水线早期写入上下文；此处读不到时回落默认组，
// 与「未启用分组」保持同一语义。所有缓存键的构造与剔除都必须经由此函数，
// 否则同一查询在写入与剔除两侧会落到不同的键上。
func cachedGroup(ctx *DNSContext) string {
	if v, ok := ctx.Get(attrClientGroup); ok {
		if s, ok := v.(string); ok && s != "" {
			return s
		}
	}
	return core.DefaultClientGroupID
}
