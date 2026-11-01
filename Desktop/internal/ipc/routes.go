package ipc

import "net/http"

// registerRoutes 注册全部 IPC / Web 控制台 HTTP 路由。
//
// 路由表从 server.go 拆出，避免该文件随功能增长触碰 600 行上限。
// 除免鉴权的少量路由（/events、/health、/meta 与 auth 登录族）外，
// 一律经 withAuth 包装。
func (s *Server) registerRoutes(mux *http.ServeMux) {
	// DNS 启停与状态
	mux.HandleFunc("/api/v1/dns/start", s.withAuth(s.handleDNSStart))
	mux.HandleFunc("/api/v1/dns/stop", s.withAuth(s.handleDNSStop))
	mux.HandleFunc("/api/v1/status", s.withAuth(s.handleStatus))

	// 网卡接管
	mux.HandleFunc("/api/v1/takeover/enable", s.withAuth(s.handleTakeoverEnable))
	mux.HandleFunc("/api/v1/takeover/disable", s.withAuth(s.handleTakeoverDisable))
	mux.HandleFunc("/api/v1/adapters", s.withAuth(s.handleAdapters))
	mux.HandleFunc("/api/v1/takeover/adapter", s.withAuth(s.handleAdapterTakeover))
	mux.HandleFunc("/api/v1/takeover/emergency-restore", s.withAuth(s.handleEmergencyRestore))

	// 上游与引导
	mux.HandleFunc("/api/v1/upstream", s.withAuth(s.handleUpstreamConfigure))
	mux.HandleFunc("/api/v1/upstream/configure", s.withAuth(s.handleUpstreamConfigure))
	mux.HandleFunc("/api/v1/upstream/test", s.withAuth(s.handleUpstreamTest))
	mux.HandleFunc("/api/v1/upstream/stamp", s.withAuth(s.handleParseStamp))
	mux.HandleFunc("/api/v1/bootstrap/configure", s.withAuth(s.handleBootstrapConfigure))

	// 缓存
	mux.HandleFunc("/api/v1/cache/stats", s.withAuth(s.handleCacheStats))
	mux.HandleFunc("/api/v1/cache/entries", s.withAuth(s.handleCacheEntries))
	mux.HandleFunc("/api/v1/cache/top", s.withAuth(s.handleCacheTop))
	mux.HandleFunc("/api/v1/cache/clear", s.withAuth(s.handleCacheClear))
	mux.HandleFunc("/api/v1/cache/config", s.withAuth(s.handleCacheConfig))
	mux.HandleFunc("/api/v1/cache/persist", s.withAuth(s.handleCachePersist))
	mux.HandleFunc("/api/v1/cache/dump", s.withAuth(s.handleCacheDump))
	mux.HandleFunc("/api/v1/cache/load", s.withAuth(s.handleCacheLoad))

	// 查询日志
	mux.HandleFunc("/api/v1/querylog/search", s.withAuth(s.handleQueryLogSearch))
	mux.HandleFunc("/api/v1/querylog/stats", s.withAuth(s.handleQueryLogStats))
	mux.HandleFunc("/api/v1/querylog/clear", s.withAuth(s.handleQueryLogClear))
	mux.HandleFunc("/api/v1/querylog/config", s.withAuth(s.handleQueryLogConfig))

	// 过滤规则
	mux.HandleFunc("/api/v1/filter/stats", s.withAuth(s.handleFilterStats))
	mux.HandleFunc("/api/v1/filter/config", s.withAuth(s.handleFilterConfig))
	mux.HandleFunc("/api/v1/filter/lists", s.withAuth(s.handleFilterLists))
	mux.HandleFunc("/api/v1/filter/lists/add", s.withAuth(s.handleFilterListAdd))
	mux.HandleFunc("/api/v1/filter/lists/update", s.withAuth(s.handleFilterListUpdate))
	mux.HandleFunc("/api/v1/filter/lists/delete", s.withAuth(s.handleFilterListDelete))
	mux.HandleFunc("/api/v1/filter/lists/refresh", s.withAuth(s.handleFilterListRefresh))
	mux.HandleFunc("/api/v1/filter/rules", s.withAuth(s.handleFilterRules))
	mux.HandleFunc("/api/v1/filter/check", s.withAuth(s.handleFilterCheck))
	mux.HandleFunc("/api/v1/filter/schedule", s.withAuth(s.handleFilterSchedule))
	mux.HandleFunc("/api/v1/filter/pause", s.withAuth(s.handleFilterPause))
	mux.HandleFunc("/api/v1/filter/services", s.withAuth(s.handleBlockedServices))

	// 局域网与隐私加固
	mux.HandleFunc("/api/v1/dns/lan", s.withAuth(s.handleLANStatus))
	mux.HandleFunc("/api/v1/dns/lan/configure", s.withAuth(s.handleLANConfigure))
	mux.HandleFunc("/api/v1/dns/lan/firewall", s.withAuth(s.handleFirewallConfigure))
	mux.HandleFunc("/api/v1/dns/access/configure", s.withAuth(s.handleAccessConfigure))
	mux.HandleFunc("/api/v1/dns/ratelimit/configure", s.withAuth(s.handleRateLimitConfigure))
	mux.HandleFunc("/api/v1/dns/dns64/configure", s.withAuth(s.handleDNS64Configure))
	mux.HandleFunc("/api/v1/dns/unqualified/configure", s.withAuth(s.handleUnqualifiedConfigure))
	mux.HandleFunc("/api/v1/dns/privacy/configure", s.withAuth(s.handlePrivacyConfigure))
	mux.HandleFunc("/api/v1/dns/rebind/configure", s.withAuth(s.handleRebindConfigure))
	mux.HandleFunc("/api/v1/dns/hosts/configure", s.withAuth(s.handleHostsConfigure))
	mux.HandleFunc("/api/v1/dns/rewrite/rules", s.withAuth(s.handleRewriteRules))
	mux.HandleFunc("/api/v1/dns/rewrite/configure", s.withAuth(s.handleRewriteConfigure))
	mux.HandleFunc("/api/v1/dns/zone/config", s.withAuth(s.handleZoneConfig))
	mux.HandleFunc("/api/v1/dns/zone/test", s.withAuth(s.handleZoneTest))
	mux.HandleFunc("/api/v1/safesearch/config", s.withAuth(s.handleSafeSearch))
	mux.HandleFunc("/api/v1/filter/safebrowsing", s.withAuth(s.handleSafeBrowsing))

	// 加密 DNS 服务（证书与监听器配置）
	mux.HandleFunc("/api/v1/encrypted/dns/status", s.withAuth(s.handleEncryptedDNSStatus))
	mux.HandleFunc("/api/v1/encrypted/dns/configure", s.withAuth(s.handleEncryptedDNSConfigure))
	mux.HandleFunc("/api/v1/encrypted/dns/cert/generate", s.withAuth(s.handleEncryptedCertGenerate))
	mux.HandleFunc("/api/v1/encrypted/dns/cert/import", s.withAuth(s.handleEncryptedCertImport))
	mux.HandleFunc("/api/v1/encrypted/dns/acl", s.withAuth(s.handleEncryptedDNSACL))
	// 描述文件是二进制文件，且需支持从设备直接打开链接下载（不带自定义
	// 请求头），故不经 withAuth 的 JSON 包装，令牌由处理器自己从 query 取
	mux.HandleFunc("/api/v1/encrypted/mobileconfig", s.handleEncryptedMobileConfig)

	// 客户端与分组
	mux.HandleFunc("/api/v1/clients", s.withAuth(s.handleClients))
	mux.HandleFunc("/api/v1/clients/alias", s.withAuth(s.handleClientAlias))
	mux.HandleFunc("/api/v1/clients/groups", s.withAuth(s.handleClientGroups))

	// ECS
	mux.HandleFunc("/api/v1/dns/ecs/configure", s.withAuth(s.handleECSConfigure))

	// 实时事件（WebSocket 升级，自行鉴权）与端口诊断
	mux.HandleFunc("/api/v1/events", s.handleEvents)
	mux.HandleFunc("/api/v1/portcheck", s.withAuth(s.handlePortCheck))
	mux.HandleFunc("/api/v1/portcheck/autofix", s.withAuth(s.handlePortAutofix))
	mux.HandleFunc("/api/v1/health", s.handleHealth)
	mux.HandleFunc("/api/v1/meta", s.handleMeta)
	mux.HandleFunc("/api/v1/service/status", s.withAuth(s.handleServiceStatus))

	// Web 远程管理与认证路由
	mux.HandleFunc("/api/v1/auth/status", s.handleAuthStatus)
	mux.HandleFunc("/api/v1/auth/login", s.handleAuthLogin)
	mux.HandleFunc("/api/v1/auth/logout", s.withAuth(s.handleAuthLogout))
	mux.HandleFunc("/api/v1/auth/setup", s.handleAuthSetup)
	mux.HandleFunc("/api/v1/auth/password", s.withAuth(s.handleAuthPassword))
	mux.HandleFunc("/api/v1/auth/background", s.handleAuthBackground)
	mux.HandleFunc("/api/v1/auth/background/image", s.handleAuthBackgroundImage)
	mux.HandleFunc("/api/v1/web/status", s.withAuth(s.handleWebStatus))
	mux.HandleFunc("/api/v1/web/configure", s.withAuth(s.handleWebConfigure))
	mux.HandleFunc("/api/v1/web/firewall", s.withAuth(s.handleWebFirewall))

	// SPA 静态资源路由回退（必须最后注册）
	mux.HandleFunc("/", s.handleStaticSPA)
}
