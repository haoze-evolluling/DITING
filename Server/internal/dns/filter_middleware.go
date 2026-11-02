package dns

import (
	"net"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewFilterMiddleware 创建规则过滤与拦截流水线中间件
func NewFilterMiddleware(engine *core.RuleEngine) Middleware {
	return NewFilterMiddlewareWithGroups(engine, nil)
}

// NewFilterMiddlewareWithGroups 创建带客户端分组感知的规则过滤中间件。
//
// groupResolver 是取值函数：分组热更新会替换解析器实例，流水线却只装配一次，
// 按值捕获旧实例会让新分组规则永久不生效。为 nil 时等价于按默认组评估。
func NewFilterMiddlewareWithGroups(engine *core.RuleEngine, groupResolver func() *core.GroupResolver) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if engine == nil || !engine.IsEnabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(q.Name)), ".")
		if domain == "" {
			return next()
		}

		// 解析客户端所属分组（未启用分组或未命中时回落 default）
		groupID := core.DefaultClientGroupID
		if groupResolver != nil && ctx.ClientIP != nil {
			if gr := groupResolver(); gr != nil {
				groupID = gr.Resolve(ctx.ClientIP)
			}
		}

		res := engine.MatchForGroup(domain, q.Qtype, groupID)

		// 分时拦截窗口外：整体放行，标记原因供日志观测
		if res.Action == "pass" && res.Reason == core.ReasonScheduleInactive {
			ctx.Set("filter_action", "pass")
			ctx.Set("filter_blocked", false)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_schedule_inactive", true)
			return next()
		}

		// 服务级周计划窗口外：仅放行这一个服务，其余规则照常生效
		if res.Action == "pass" && res.Reason == core.ReasonServiceScheduleInactive {
			ctx.Set("filter_action", "pass")
			ctx.Set("filter_blocked", false)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_service_schedule_inactive", true)
			ctx.Set(attrClientGroup, groupID)
			return next()
		}

		// 重写必须早于拦截判定：两者互斥，重写命中时不应再生成阻断应答
		if res.IsRewrite() {
			ctx.Resp = buildRewriteResponse(ctx.Req, *res.Rewritten)
			ctx.Set("source", "dnsrewrite")
			ctx.Set("cache_hit", "dnsrewrite")
			ctx.Set("filter_action", "rewrite")
			ctx.Set("filter_blocked", false)
			ctx.Set("filter_rule", res.MatchedRule)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_list", res.ListName)
			ctx.Set(attrClientGroup, groupID)
			return nil
		}

		if res.Blocked {
			// 构建阻断响应报文并短路返回（组级拦截方式可覆盖全局）
			blockCfg := engine.GetConfig()
			if override := engine.GroupBlockMode(groupID); override != "" {
				blockCfg.BlockMode = override
			}
			resp := BuildBlockedResponse(ctx.Req, blockCfg)
			ctx.Resp = resp
			ctx.Set("filter_action", "block")
			ctx.Set("filter_blocked", true)
			ctx.Set("filter_rule", res.MatchedRule)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_list", res.ListName)
			ctx.Set(attrClientGroup, groupID)
			return nil
		}

		if res.Action == "allow" {
			ctx.Set("filter_action", "allow")
			ctx.Set("filter_blocked", false)
			ctx.Set("filter_rule", res.MatchedRule)
			ctx.Set("filter_reason", res.Reason)
			ctx.Set("filter_list", res.ListName)
		}

		return next()
	}
}

// buildRewriteResponse 依据 $dnsrewrite 规则组装应答报文。
//
// 与 BuildBlockedResponse 的区别在语义而不只是内容：这里返回的是规则
// 明确声明的应答，Rcode 与记录都来自规则本身，不受 BlockMode 影响。
// Records 为空且 Rcode 为 NOERROR 时是有意为之的权威 NODATA，
// 用于让「该名字只有 A 记录」的内网域名不因查询 AAAA 而外泄到上游。
func buildRewriteResponse(req *dns.Msg, res core.RewriteResult) *dns.Msg {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Authoritative = true
	resp.RecursionAvailable = true
	resp.Rcode = res.RCode
	resp.Answer = res.Records
	return resp
}

// BuildBlockedResponse 依据配置策略组装阻断 DNS 应答报文。
//
// 导出是因为声誉查询（safe browsing / 家长控制）命中时也需要给出与本地
// 规则拦截完全一致的应答形式：用户配置的 BlockMode 是全局策略，
// 不该因为拦截来自哪一层而给出不同的失败形态。
func BuildBlockedResponse(req *dns.Msg, cfg core.FilterConfig) *dns.Msg {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Authoritative = true
	resp.RecursionAvailable = true

	q := req.Question[0]

	switch cfg.BlockMode {
	case core.BlockModeNXDOMAIN:
		resp.Rcode = dns.RcodeNameError
		return resp

	case core.BlockModeRefused:
		resp.Rcode = dns.RcodeRefused
		return resp

	case core.BlockModeNullIP:
		fallthrough
	default:
		resp.Rcode = dns.RcodeSuccess

		switch q.Qtype {
		case dns.TypeA:
			ip := net.ParseIP(cfg.BlockingIPv4)
			if ip == nil {
				ip = net.IPv4zero
			}
			ip = ip.To4()
			if ip != nil {
				rr := &dns.A{
					Hdr: dns.RR_Header{
						Name:   q.Name,
						Rrtype: dns.TypeA,
						Class:  dns.ClassINET,
						Ttl:    core.DefaultRuleTTL,
					},
					A: ip,
				}
				resp.Answer = append(resp.Answer, rr)
			}

		case dns.TypeAAAA:
			ip := net.ParseIP(cfg.BlockingIPv6)
			if ip == nil {
				ip = net.IPv6zero
			}
			rr := &dns.AAAA{
				Hdr: dns.RR_Header{
					Name:   q.Name,
					Rrtype: dns.TypeAAAA,
					Class:  dns.ClassINET,
					Ttl:    core.DefaultRuleTTL,
				},
				AAAA: ip,
			}
			resp.Answer = append(resp.Answer, rr)

		default:
			// 对于 MX/TXT 等非常规类型，保持 NOERROR 且 Answer 留空 (NODATA)
		}

		return resp
	}
}
