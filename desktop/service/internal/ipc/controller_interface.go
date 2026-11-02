package ipc

import (
	"context"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/platform"
	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

// ServiceController 抽象服务核心控制操作接口
type ServiceController interface {
	StartDNS(ctx context.Context) error
	StopDNS(ctx context.Context) error
	EnableTakeover(ctx context.Context) error
	DisableTakeover(ctx context.Context) error
	// EmergencyRestore 按落盘的接管快照把系统 DNS 恢复为接管前的样子，用于软件异常退出后
	// 无法上网的应急场景。桌面窗口与局域网控制台走同一接口。
	EmergencyRestore(ctx context.Context) (*EmergencyRestoreResponse, error)
	GetStatus(ctx context.Context) (*StatusResponse, error)
	// GetCoreServiceStatus 返回宿主机后台核心服务的真实运行状态与自启托管情况。
	//
	// Web 控制台无法直接访问桌面端进程，需经此接口获取权威状态，
	// 避免以"未安装/未检测到/未配置开机启动"等占位文案误导用户。
	GetCoreServiceStatus(ctx context.Context) (*platform.CoreServiceStatus, error)
	CheckPortConflicts(ctx context.Context) (*platform.PortCheckResult, error)
	AutofixPortConflicts(ctx context.Context, startDNS bool) (*platform.PortCheckResult, error)
	GetAdapters(ctx context.Context) ([]platform.AdapterInfo, error)
	ConfigureUpstream(ctx context.Context, req ConfigureUpstreamRequest) error
	GetUpstreamConfig(ctx context.Context) (*core.ResolverConfig, error)
	TestUpstream(ctx context.Context, req TestUpstreamRequest) (*TestUpstreamResponse, error)
	SetAdapterTakeover(ctx context.Context, req AdapterTakeoverRequest) error
	GetCacheStats(ctx context.Context) (*core.CacheStats, error)
	GetCacheEntries(ctx context.Context, query string, limit int) (*CacheEntriesResponse, error)
	GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error)
	ClearCache(ctx context.Context) error
	GetCacheConfig(ctx context.Context) (*core.CacheConfig, error)
	UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error
	// CachePersistStatus 返回缓存落盘状态与排除规则概览
	CachePersistStatus(ctx context.Context) (*CachePersistResponse, error)
	// DumpCache 立即把内存缓存落盘
	DumpCache(ctx context.Context) (*CachePersistResponse, error)
	// LoadCache 从落盘文件恢复缓存
	LoadCache(ctx context.Context) (*CachePersistResponse, error)
	GetFilterStats(ctx context.Context) (*core.FilterStats, error)
	GetFilterConfig(ctx context.Context) (*core.FilterConfig, error)
	UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error
	GetFilterLists(ctx context.Context) ([]core.FilterList, error)
	AddFilterList(ctx context.Context, list core.FilterList) error
	UpdateFilterList(ctx context.Context, list core.FilterList) error
	DeleteFilterList(ctx context.Context, id string) error
	RefreshFilterLists(ctx context.Context, id string) error
	// GetBlockedServices 返回内置阻断服务目录与当前选择
	GetBlockedServices(ctx context.Context) (*BlockedServicesResponse, error)
	// ConfigureBlockedServices 更新内置服务拦截选择并热重载规则
	ConfigureBlockedServices(ctx context.Context, req ConfigureBlockedServicesRequest) error
	GetCustomRules(ctx context.Context) ([]string, error)
	SetCustomRules(ctx context.Context, rules []string) error
	CheckHostRule(ctx context.Context, domain string, qtype uint16) (*core.CheckHostResult, error)
	GetBlockingSchedule(ctx context.Context) (*ScheduleConfigResponse, error)
	ConfigureBlockingSchedule(ctx context.Context, req ConfigureScheduleRequest) error
	GetFilterPause(ctx context.Context) (*FilterPauseResponse, error)
	SetFilterPause(ctx context.Context, req FilterPauseRequest) error
	GetClientGroups(ctx context.Context) (*ClientGroupConfigResponse, error)
	ConfigureClientGroups(ctx context.Context, req ConfigureClientGroupsRequest) error
	GetLANStatus(ctx context.Context) (*LANStatusResponse, error)
	ConfigureLAN(ctx context.Context, req ConfigureLANRequest) error
	ConfigureFirewall(ctx context.Context, enable bool) error
	GetWebStatus(ctx context.Context) (*WebStatusResponse, error)
	ConfigureWeb(ctx context.Context, req ConfigureWebRequest) error
	ConfigureWebFirewall(ctx context.Context, enable bool) error
	GetAuthStatus(ctx context.Context) (*AuthStatusResponse, error)
	Login(ctx context.Context, req LoginRequest, clientIP string) (*LoginResponse, error)
	Logout(ctx context.Context, token string) error
	SetupAuth(ctx context.Context, req SetupAuthRequest) error
	ChangePassword(ctx context.Context, req ChangePasswordRequest, bypassOldAuth bool) error
	ValidateSession(token string) bool
	GetLoginBackground(ctx context.Context) (*LoginBackgroundResponse, error)
	SetLoginBackground(ctx context.Context, req SetLoginBackgroundRequest) error
	ResetLoginBackground(ctx context.Context) error
	GetLoginBackgroundImage(ctx context.Context) ([]byte, string, time.Time, error)
	VerifyAdminPassword(ctx context.Context, plainPassword string) bool
	VerifyAdminPasswordWithIP(ctx context.Context, clientIP, plainPassword string) (bool, error)
	IsAuthInitialized() bool
	ConfigureAccess(ctx context.Context, req ConfigureAccessRequest) error
	ConfigureRateLimit(ctx context.Context, req ConfigureRateLimitRequest) error
	ConfigureDNS64(ctx context.Context, req ConfigureDNS64Request) error
	ConfigureBlockUnqualified(ctx context.Context, req ConfigureBlockUnqualifiedRequest) error
	GetRewriteRules(ctx context.Context) ([]core.RewriteRule, error)
	AddRewriteRule(ctx context.Context, rule core.RewriteRule) error
	DeleteRewriteRule(ctx context.Context, domain string) error
	ConfigureRewrite(ctx context.Context, req ConfigureRewriteRequest) error
	// GetZoneConfig 返回本地权威区（zone 文件）配置与各区构建结果
	GetZoneConfig(ctx context.Context) (*ZoneConfigResponse, error)
	// ConfigureZone 更新本地权威区配置并重建索引
	ConfigureZone(ctx context.Context, req ConfigureZoneRequest) error
	// GetSafeBrowsing 返回恶意网址库与家长控制的配置与统计
	GetSafeBrowsing(ctx context.Context) (*SafeBrowsingResponse, error)
	// ConfigureSafeBrowsing 更新声誉查询配置
	ConfigureSafeBrowsing(ctx context.Context, req ConfigureSafeBrowsingRequest) error
	// GetEncryptedDNS 返回加密 DNS 服务的配置、证书摘要与目录
	GetEncryptedDNS(ctx context.Context) (*EncryptedDNSStatusResponse, error)
	// ConfigureEncryptedDNS 更新加密 DNS 配置与证书配置
	ConfigureEncryptedDNS(ctx context.Context, req ConfigureEncryptedDNSRequest) error
	// GenerateEncryptedCert 生成或重新签发自签证书
	GenerateEncryptedCert(ctx context.Context, req GenerateCertRequest) error
	// ImportEncryptedCert 导入一对 PEM 或一个 PKCS#12 容器作为服务端证书
	ImportEncryptedCert(ctx context.Context, req ImportCertRequest) error
	// BuildEncryptedMobileConfig 生成 Apple 配置描述文件；
	// protocol 为空时按当前启用的监听器挑选
	BuildEncryptedMobileConfig(ctx context.Context, protocol string) ([]byte, error)
	// ConfigureEncryptedACL 更新反向代理可信来源；全放行需已确认
	ConfigureEncryptedACL(ctx context.Context, req ConfigureACLRequest) error
	GetSafeSearch(ctx context.Context) (*SafeSearchConfigResponse, error)
	ConfigureSafeSearch(ctx context.Context, req ConfigureSafeSearchRequest) error
	GetClients(ctx context.Context) ([]core.ClientInfo, error)
	ConfigureClientAlias(ctx context.Context, req ConfigureClientAliasRequest) error
	ConfigureECS(ctx context.Context, req ConfigureECSRequest) error
	ConfigurePrivacy(ctx context.Context, req ConfigurePrivacyRequest) error
	ConfigureRebind(ctx context.Context, req ConfigureRebindRequest) error
	ConfigureHosts(ctx context.Context, req ConfigureHostsRequest) error
	GetQueryLog(ctx context.Context, query querylog.SearchQuery) (*querylog.SearchResult, error)
	GetQueryStats(ctx context.Context) (*QueryStatsResponse, error)
	ClearQueryLog(ctx context.Context) error
	GetQueryLogConfig(ctx context.Context) (*querylog.QueryLogConfig, error)
	UpdateQueryLogConfig(ctx context.Context, cfg querylog.QueryLogConfig) error
}
