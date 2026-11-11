package dns

import (
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewFilterResponseMiddleware 创建响应侧别名链复检中间件（深链拦截，默认关闭）。
//
// 做法同 blocky（isResponseBlocked）与 dnscrypt-proxy（别名链上限 8）：纯 CNAME 换域可绕过
// 只检查 QNAME 的拦截，因此在应答装配后二次复检。
//
// 必须包裹缓存（echMw 之后、cacheMw 之前）：缓存命中路径不执行 next()（见
// cache_middleware.go），只有外层中间件才能覆盖缓存响应；同时保证热关闭后立即生效，不等 TTL 过期。
//
// groupResolver 是取值函数而非实例：分组热更新会替换实例，流水线只装配一次。
func NewFilterResponseMiddleware(
	engine *core.RuleEngine,
	groupResolver func() *core.GroupResolver,
	enabled func() bool,
	cache ...*core.DNSCache,
) Middleware {
	var c *core.DNSCache
	if len(cache) > 0 {
		c = cache[0]
	}

	return func(ctx *DNSContext, next func() error) error {
		err := next()

		if enabled == nil || !enabled() || engine == nil || !engine.IsEnabled() {
			return err
		}
		if ctx.Req == nil || ctx.Resp == nil || len(ctx.Req.Question) == 0 {
			return err
		}
		// 已阻断（含规则/访问控制/限流/Rebinding）无需重复处理
		if blocked, ok := ctx.Get("filter_blocked"); ok && blocked == true {
			return err
		}
		// 本地权威应答（hosts / rewrite / SUDN）不参与黑名单复检，避免误杀内部域名
		if isLocallyServedSource(ctx) {
			return err
		}
		// 仅对成功应答复检（NXDOMAIN/SERVFAIL/REFUSED 无别名链语义）
		if ctx.Resp.Rcode != dns.RcodeSuccess {
			return err
		}

		q := ctx.Req.Question[0]
		qname := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(q.Name)), ".")

		groupID := core.DefaultClientGroupID
		if groupResolver != nil && ctx.ClientIP != nil {
			if gr := groupResolver(); gr != nil {
				groupID = gr.Resolve(ctx.ClientIP)
			}
		}

		res := engine.MatchResponse(ctx.Resp, qname, q.Qtype, groupID)
		if !res.Blocked {
			return err
		}

		// 依据组级拦截方式覆盖组装阻断应答，并就地替换（复用既有 EDE / 指标 / 日志上报路径）
		blockCfg := engine.GetConfig()
		if override := engine.GroupBlockMode(groupID); override != "" {
			blockCfg.BlockMode = override
		}
		ctx.Resp = BuildBlockedResponse(ctx.Req, blockCfg)
		ctx.Set("filter_action", "block")
		ctx.Set("filter_blocked", true)
		ctx.Set("filter_rule", res.MatchedRule)
		ctx.Set("filter_reason", res.Reason)
		ctx.Set("filter_list", res.ListName)
		ctx.Set(attrClientGroup, groupID)
		ctx.Set("response_filtered", true)

		// 同步剔除缓存中被投毒（别名指向黑名单域）的条目，防止后续命中重放。
		// 必须按本条查询所属分组剔除：分组键带组后缀，删默认组键是空操作。
		if c != nil {
			c.RemoveForGroup(ctx.Req, groupID)
		}

		return err
	}
}

// isLocallyServedSource 判断响应是否来自本地权威数据源（hosts / rewrite / SUDN）。
func isLocallyServedSource(ctx *DNSContext) bool {
	val, ok := ctx.Get("source")
	if !ok {
		return false
	}
	src, ok := val.(string)
	if !ok {
		return false
	}
	switch src {
	case "hosts", "rewrite", "sudn", "sudn_ddr", "locally_served_zone":
		return true
	}
	return false
}
