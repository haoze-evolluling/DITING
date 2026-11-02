package dns

import (
	"strings"
)

// NewDDRMiddleware 创建 DDR（RFC 9462）指定解析器发现中间件。
//
// 必须注册在 SUDN 之前：SUDN 会对整个 resolver.arpa 返回 NODATA 以防止
// 探测外泄，DDR 只有在它之前才有机会接管 _dns.resolver.arpa.。
//
// 开关与内容都通过回调动态读取：加密监听器是随配置热重建的，
// 在这条流水线里缓存一份快照会立刻过期。
//
// 默认关闭是刻意的：DDR 会让客户端在证书不受信任时直接失去解析能力，
// 而它带来的收益（少填一个地址）远不抵这个风险。
func NewDDRMiddleware(enabled func() bool, answer func() DDRAnswer) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}
		if enabled == nil || !enabled() {
			return next()
		}

		q := ctx.Req.Question[0]
		if !strings.EqualFold(strings.TrimSpace(q.Name), ddrQueryName) {
			return next()
		}

		var cfg DDRAnswer
		if answer != nil {
			cfg = answer()
		}
		// 没有任何在听的加密入口时交回 SUDN：让它照旧返回 NODATA，
		// 而不是由这里给出一个空应答把「有服务但没配」和「根本没开」混为一谈
		if cfg.IsEmpty() {
			return next()
		}

		resp := BuildDDRResponse(ctx.Req, cfg)
		if resp == nil {
			return next()
		}

		ctx.Resp = resp
		ctx.Set("ddr_handled", true)
		ctx.Set("source", "ddr")
		return nil
	}
}

// BuildDDRAnswer 从加密监听状态汇总一份 DDR 广播内容。
//
// 只收录真正在监听的口：广播一个绑不上的端口会让客户端把解析
// 交给一个不存在的服务，比不广播严重得多。
func BuildDDRAnswer(cfg *EncryptedServerConfig, dotListen, dohListen, doqListen string, certIPs []string) DDRAnswer {
	answer := DDRAnswer{}
	if cfg == nil {
		return answer
	}

	answer.ServerName = cfg.ServerName
	if strings.TrimSpace(dotListen) != "" && cfg.DoTEnabled {
		answer.DoTEnabled = true
		answer.DoTPort = cfg.DoTPort
	}
	if strings.TrimSpace(dohListen) != "" && cfg.DoHEnabled {
		answer.DoHEnabled = true
		answer.DoHPort = cfg.DoHPort
		answer.DoHPath = cfg.DoHPath
	}
	if strings.TrimSpace(doqListen) != "" && cfg.DoQEnabled {
		answer.DoQEnabled = true
		answer.DoQPort = cfg.DoQPort
	}
	answer.CertHasIPs = ddrCertHasIPs(certIPs)
	return answer
}
