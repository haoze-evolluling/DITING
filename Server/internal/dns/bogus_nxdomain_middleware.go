package dns

import (
	"fmt"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewBogusNXDomainMiddleware 创建伪应答纠正中间件。
//
// 部分网络在域名不存在时不返回 NXDOMAIN，而是返回一个固定的导航/广告页地址，
// 且 Rcode 为 NOERROR。客户端据此认为域名存在，解析结果还会被正常缓存。
// 本中间件在响应侧识别这类地址并就地改写为 NXDOMAIN。
//
// matcher 由调用方持有并支持热替换（传 func 而非实例）：配置更新后应立即生效，
// 而中间件只在启动时装配一次。
//
// 注册位置必须是「缓存之后、回源之前」：
// 放在缓存之前会让 NXDOMAIN 纠正无法被缓存，伪地址仍可能被写入缓存；
// 放在回源之后则已写入的伪记录无法被撤回。
func NewBogusNXDomainMiddleware(matcher func() *core.BogusNXDomainMatcher) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		err := next()

		if matcher == nil || ctx.Resp == nil || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return err
		}

		m := matcher()
		if m == nil || m.Size() == 0 {
			return err
		}

		// 已由其它中间件判定为拦截：保留其结论与标记，避免二次改写混淆归因
		if blocked, ok := ctx.Get("filter_blocked"); ok && blocked == true {
			return err
		}
		// 只处理成功的应答。错误应答本就由上游故障路径处理，
		// 对其改写会把"网络不通"伪装成"域名不存在"。
		if ctx.Resp.Rcode != dns.RcodeSuccess {
			return err
		}

		ip, hit := m.FindInMsg(ctx.Resp)
		if !hit {
			return err
		}

		q := ctx.Req.Question[0]

		// 复刻 BuildBlockedResponse 的 NXDOMAIN 形态，并打上与规则拦截一致的标记，
		// 使 EDE（Blocked）、查询日志分类与统计口径无需为这条路径单开分支。
		resp := new(dns.Msg)
		resp.SetRcode(ctx.Req, dns.RcodeNameError)
		resp.Authoritative = true
		resp.RecursionAvailable = true
		ctx.Resp = resp

		reason := fmt.Sprintf("伪应答纠正: %s 解析为 %s，判定为上游劫持", q.Name, ip.String())
		ctx.Set("bogus_nxdomain", true)
		ctx.Set("filter_action", "block")
		ctx.Set("filter_blocked", true)
		ctx.Set("filter_reason", reason)
		ctx.Set("filter_list", "bogus-nxdomain")

		return err
	}
}
