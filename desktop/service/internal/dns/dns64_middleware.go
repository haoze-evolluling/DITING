package dns

import (
	"context"
	"math"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// NewDNS64Middleware 创建 DNS64 IPv6-only 过渡合成洋葱中间件。
// 借鉴自 blocky (dns64_resolver.go)、AdGuard Home (dns64.go) 与 RFC 6147 规范。
// 当 IPv6 客户端查询 AAAA 记录且上游无 IPv6 响应时，自动查询 A 记录并按 RFC 6052 合成 AAAA 响应。
func NewDNS64Middleware(synth *core.DNS64Synthesizer, resolver core.Resolver) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if synth == nil || !synth.IsEnabled() || resolver == nil || ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		q := ctx.Req.Question[0]
		if q.Qtype != dns.TypeAAAA {
			return next()
		}

		// 优先执行下游解析链（查本地缓存与上游）
		if err := next(); err != nil {
			return err
		}

		// RFC 6147 Section 5.1.2: 仅当原有响应为 NOERROR 时才触发合成；若为 NXDOMAIN/SERVFAIL 则不得合成
		if ctx.Resp == nil || ctx.Resp.Rcode != dns.RcodeSuccess {
			return nil
		}

		// RFC 6147 Section 5.1.1 & 5.1.4: 若应答中已包含非排除集的有效 AAAA 记录，则不得进行合成
		if synth.HasValidAAAARecords(ctx.Resp) {
			return nil
		}

		// 发起同名 A 记录解析请求
		reqCtx := ctx.Context
		if reqCtx == nil {
			reqCtx = context.Background()
		}

		aReq := new(dns.Msg)
		aReq.SetQuestion(q.Name, dns.TypeA)
		aReq.RecursionDesired = true

		aResp, err := resolver.Exchange(reqCtx, aReq)
		if err != nil || aResp == nil || aResp.Rcode != dns.RcodeSuccess || len(aResp.Answer) == 0 {
			return nil
		}

		var aRecords []*dns.A
		var cnameRecords []*dns.CNAME
		var dnameRecords []*dns.DNAME

		minTTL := uint32(math.MaxUint32)
		for _, rr := range aResp.Answer {
			switch r := rr.(type) {
			case *dns.A:
				aRecords = append(aRecords, r)
				if r.Hdr.Ttl < minTTL {
					minTTL = r.Hdr.Ttl
				}
			case *dns.CNAME:
				cnameRecords = append(cnameRecords, r)
				if r.Hdr.Ttl < minTTL {
					minTTL = r.Hdr.Ttl
				}
			case *dns.DNAME:
				dnameRecords = append(dnameRecords, r)
				if r.Hdr.Ttl < minTTL {
					minTTL = r.Hdr.Ttl
				}
			}
		}

		if len(aRecords) == 0 {
			return nil
		}

		if minTTL == math.MaxUint32 {
			minTTL = 60
		}

		// 按照 RFC 6147 Section 5.1.7 使用全链路最小 TTL 合成 AAAA
		aaaaRecords := synth.SynthesizeFromAWithTTL(aRecords, minTTL)
		if len(aaaaRecords) == 0 {
			return nil
		}

		// RFC 6147 Section 5.1.2: 保留并补齐 CNAME/DNAME 递归追链，防止客户端别名丢失
		existingRRs := make(map[string]struct{})
		for _, rr := range ctx.Resp.Answer {
			existingRRs[rr.String()] = struct{}{}
		}

		for _, cname := range cnameRecords {
			if _, exists := existingRRs[cname.String()]; !exists {
				ctx.Resp.Answer = append(ctx.Resp.Answer, cname)
				existingRRs[cname.String()] = struct{}{}
			}
		}
		for _, dname := range dnameRecords {
			if _, exists := existingRRs[dname.String()]; !exists {
				ctx.Resp.Answer = append(ctx.Resp.Answer, dname)
				existingRRs[dname.String()] = struct{}{}
			}
		}

		// 将合成的 AAAA 记录注入响应应答区
		for _, aaaa := range aaaaRecords {
			ctx.Resp.Answer = append(ctx.Resp.Answer, aaaa)
		}
		ctx.Resp.Rcode = dns.RcodeSuccess
		ctx.Set("dns64_synthesized", true)
		return nil
	}
}
