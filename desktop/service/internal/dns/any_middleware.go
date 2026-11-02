package dns

import (
	"strings"

	"github.com/miekg/dns"
)

// RFC8482HINFO 为 RFC 8482 规定的 ANY 最小化应答内容
const RFC8482HINFO = "RFC8482"

// NewANYMiddleware 创建 ANY 查询最小化应答中间件。
//
// ANY (QtypeANY) 查询在实践中有两个问题：一是被大量用于 DNS 放大攻击，
// 二是它按定义返回"该名字的全部记录"，会让按记录类型下发的拦截策略失效——
// 客户端只要查 ANY 就能同时拿到 A 与 AAAA，绕过针对其中一种类型的阻断。
//
// 两种应答形式（RFC 8482 §4.2/§4.3）：
//   - notimp：NOTIMP，明确表示不支持该查询。更保守，客户端不会误当成有效解析。
//   - rfc8482：NOERROR + HINFO("RFC8482")，语义更准确，但需要客户端理解这一约定。
//
// mode 由调用方动态传入以支持热更新；未知取值按 notimp 处理。
//
// 注册位置在 unqualified 之后、filter 之前：本地权威应答（Hosts / 自定义重写）
// 与前面的拦截已有结论，此处只处理真正会外泄到上游的 ANY 查询。
func NewANYMiddleware(enabled func() bool, mode func() string) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if enabled == nil || !enabled() || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		// ANY 只对 IN 类有意义；其它类别（如 CH TXT 版本查询）不属于放大攻击面
		if q.Qtype != dns.TypeANY || q.Qclass != dns.ClassINET {
			return next()
		}

		// 就地给出结论并短路：ANY 查询本就只对外泄到上游才有危害，
		// 走到这里说明本地没有权威应答可用。
		resp := buildANYMinimalResponse(ctx.Req, resolvedANYMode(mode))
		ctx.Resp = resp

		ctx.Set("filter_blocked", true)
		ctx.Set("filter_rule", "BLOCK_ANY")
		ctx.Set("filter_reason", "ANY query minimized per RFC 8482")
		ctx.Set("any_blocked", true)
		return nil
	}
}

// resolvedANYMode 归一化模式取值，未知或空值回落到 notimp
func resolvedANYMode(mode func() string) string {
	if mode == nil {
		return "notimp"
	}
	switch strings.ToLower(strings.TrimSpace(mode())) {
	case "rfc8482":
		return "rfc8482"
	default:
		return "notimp"
	}
}

// buildANYMinimalResponse 组装最小化应答报文
func buildANYMinimalResponse(req *dns.Msg, mode string) *dns.Msg {
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Authoritative = true
	resp.RecursionAvailable = true

	if mode != "rfc8482" {
		resp.Rcode = dns.RcodeNotImplemented
		return resp
	}

	// RFC 8482 §4.2: 返回一条 HINFO RR，CPU 固定为 "RFC8482"，
	// 使调用方能够据此区分"不支持 ANY"与"该名字确实只有 HINFO 记录"。
	q := req.Question[0]
	resp.Answer = append(resp.Answer, &dns.HINFO{
		Hdr: dns.RR_Header{
			Name:   q.Name,
			Rrtype: dns.TypeHINFO,
			Class:  dns.ClassINET,
			// TTL 取 0：这不是可缓存的事实，而是对查询形式本身的说明
			Ttl: 0,
		},
		Cpu: RFC8482HINFO,
		Os:  "",
	})
	return resp
}
