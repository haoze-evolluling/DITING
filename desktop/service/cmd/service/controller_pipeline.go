package main

import (
	"github.com/haoze-evolluling/diting/server/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/server/internal/dns"
)

// buildPipeline 装配 DNS 请求处理流水线。
//
// 中间件的注册顺序即语义的一部分，调用方不得随意调整：
//
//	metrics → EDE → ECH → client → access → ratelimit → DDR → SUDN → zone → hosts
//	→ rewrite → safesearch → IPv6 → privatePTR → unqualified → ANY → filter → safeBrowsing
//	→ rebind → filterResponse → DNS64 → ECS → cache → bogusNXDomain → upstreamRoute → forward
//
// 其中响应侧复检（filterResponse）位于 rebind 之后、DNS64 之前：
// 既包裹缓存（缓存命中也复检），又在 DNS64 合成之后获得最终应答，
// 且被 rebind 的已阻断判定短路。
//
// 伪应答纠正（bogusNXDomain）夹在缓存与回源之间，理由见该处注释。
//
// 调用方需持有 p.mu（内部对 p.cfg 的读取依赖该保护）。
func (p *program) buildPipeline() *ditingdns.Pipeline {
	metricsMw := p.newMetricsMiddleware()

	rebindMgr := p.rebindMgr
	if rebindMgr == nil {
		rebindMgr = ditingdns.NewRebindProtectionManager(p.cfg.Rebind)
	}
	// 分组标记必须在缓存之前写入，否则缓存键会退化为默认组而失去分组隔离。
	//
	// 分组解析器一律以取值函数传入：ConfigureClientGroups 会整体替换
	// p.groupResolver，而流水线只在 StartDNS 时装配一次。按值捕获旧实例
	// 会让新增分组/成员对转发路径完全不生效，API 却回复「已更新并生效」。
	groupRef := func() *core.GroupResolver {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.groupResolver
	}
	clientMw := ditingdns.NewClientMiddlewareWithGroups(p.clientResolver, groupRef)
	accessMw := ditingdns.NewAccessMiddleware(p.accessControl)
	rateLimitMw := ditingdns.NewRateLimitMiddleware(p.rateLimiter)
	edeMw := ditingdns.NewEDEMiddleware(func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.EnableEDE
	})
	echMw := ditingdns.NewECHMiddleware(func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.BlockECH
	})
	// DDR 必须排在 SUDN 之前：SUDN 会对整个 resolver.arpa 返回 NODATA
	// 以防探测外泄，晚于它注册就永远轮不到 DDR 接管
	ddrMw := ditingdns.NewDDRMiddleware(
		func() bool {
			p.mu.Lock()
			defer p.mu.Unlock()
			return p.cfg.Encrypted.Enabled && p.cfg.Encrypted.DDREnabled
		},
		func() ditingdns.DDRAnswer {
			p.mu.Lock()
			defer p.mu.Unlock()

			if p.server == nil {
				return ditingdns.DDRAnswer{}
			}
			var certIPs []string
			if p.certManager != nil {
				certIPs = p.certManager.Info().IPAddresses
			}
			// 只在真正监听的端口上广播：广播一个绑不上的端口，
			// 等于把客户端的解析交给一个不存在的服务
			return ditingdns.BuildDDRAnswer(
				p.buildEncryptedServerConfig(),
				p.server.DoTListenAddress(),
				p.server.DoHListenAddress(),
				p.server.DoQListenAddress(),
				certIPs,
			)
		},
	)
	sudnMw := ditingdns.NewSUDNMiddleware()
	ipv6Mw := ditingdns.NewIPv6Middleware(func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.BlockIPv6
	})
	// 本地权威区排在 hosts 之前：区是对整个名字空间的显式声明，
	// 同名时以区为准；反之区的权威 NODATA 会被 hosts 的局部条目掩盖。
	zoneMw := ditingdns.NewZoneMiddleware(p.zoneEngine)
	hostsMw := ditingdns.NewHostsMiddleware(p.hostsResolver)
	rewriteMw := ditingdns.NewRewriteMiddleware(p.rewriteEngine)
	safeSearchMw := ditingdns.NewSafeSearchMiddleware(p.safeSearchEng)
	privatePTRMw := ditingdns.NewPrivatePTRMiddleware(func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.BlockPrivatePTR
	}, p.clientResolver)
	unqualifiedMw := ditingdns.NewDynamicUnqualifiedMiddleware(func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.BlockUnqualified
	})
	// ANY 最小化放在 unqualified 之后、filter 之前：
	// 本地权威应答与前置拦截已有结论，此处只拦真正会外泄到上游的 ANY 查询。
	anyMw := ditingdns.NewANYMiddleware(func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.BlockANY
	}, func() string {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.DNS.BlockANYMode
	})
	filterMw := ditingdns.NewFilterMiddlewareWithGroups(p.filterEngine, groupRef)
	// 声誉查询紧跟在本地规则之后：本地规则是免费的，先让它筛掉绝大多数请求，
	// 只有到这里仍未被拦的域名才值得花一次外部查询。它也必须在缓存之前——
	// 缓存的键里没有「谁拦的」这一维度，拦下的应答进了缓存会掩盖真实判断。
	safeBrowsingMw := ditingdns.NewSafeBrowsingMiddleware(p.safeBrowsing, func() core.FilterConfig {
		if p.filterEngine == nil {
			return core.FilterConfig{}
		}
		return p.filterEngine.GetConfig()
	})
	rebindMw := ditingdns.NewRebindMiddleware(rebindMgr, p.cache)
	filterResponseMw := ditingdns.NewFilterResponseMiddleware(p.filterEngine, groupRef, func() bool {
		p.mu.Lock()
		defer p.mu.Unlock()
		return p.cfg.Filter.FilterResponse
	}, p.cache)
	dns64Mw := ditingdns.NewDNS64Middleware(p.dns64Synth, p.resolver)
	ecsMw := ditingdns.NewECSMiddleware(p.ecsMgr)
	cacheMw := ditingdns.NewCacheMiddlewareWithGroups(p.cache, p.resolver, groupRef)
	// 伪应答纠正必须紧贴缓存之后：在缓存之前会让纠正后的 NXDOMAIN 无法被缓存，
	// 伪地址仍可能被写入；在回源之后则已写入的伪记录无法撤回。
	bogusNxMw := ditingdns.NewBogusNXDomainMiddleware(func() *core.BogusNXDomainMatcher {
		if p.filterEngine == nil {
			return nil
		}
		return p.filterEngine.BogusNXDomainMatcher()
	})
	upstreamRouteMw := ditingdns.NewUpstreamRouteMiddleware(p.resolver, groupRef)
	forwardMw := ditingdns.NewForwardMiddleware(p.resolver)

	return ditingdns.NewPipeline(
		metricsMw, edeMw, echMw, clientMw, accessMw, rateLimitMw, ddrMw, sudnMw,
		zoneMw, hostsMw, rewriteMw, safeSearchMw, ipv6Mw, privatePTRMw, unqualifiedMw,
		anyMw, filterMw, safeBrowsingMw, rebindMw, filterResponseMw, dns64Mw, ecsMw, cacheMw,
		bogusNxMw, upstreamRouteMw, forwardMw,
	)
}
