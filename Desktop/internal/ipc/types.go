package ipc

import (
	"github.com/haoze-evolluling/diting/desktop/internal/core"
	"github.com/haoze-evolluling/diting/desktop/internal/platform"
	"github.com/haoze-evolluling/diting/desktop/internal/querylog"
)

// Response 通用 API JSON 响应体
type Response[T any] struct {
	Success  bool                      `json:"success"`
	Message  string                    `json:"message,omitempty"`
	Data     T                         `json:"data,omitempty"`
	Error    string                    `json:"error,omitempty"`
	Conflict *platform.PortCheckResult `json:"conflict,omitempty"`
}

// UpstreamInfo 上游 DNS 解析节点运行态信息
type UpstreamInfo struct {
	ID           string  `json:"id"`
	Protocol     string  `json:"protocol"`
	Server       string  `json:"server"`
	URL          string  `json:"url,omitempty"`
	Weight       int     `json:"weight"`
	Active       bool    `json:"active"`
	SuccessCount uint64  `json:"successCount"`
	FailureCount uint64  `json:"failureCount"`
	AvgLatencyMs float64 `json:"avgLatencyMs"`
	// PinSet 表示该上游已启用证书固定（仅暴露布尔标志，不回传指纹本身）
	PinSet bool `json:"pinSet,omitempty"`
}

// DNSStatus DNS 监听器运行状态
type DNSStatus struct {
	Running           bool                 `json:"running"`
	ListenAddresses   []string             `json:"listenAddresses"`
	AllowLAN          bool                 `json:"allowLAN"`
	LANAddresses      []string             `json:"lanAddresses,omitempty"`
	Mode              string               `json:"mode"`
	Upstreams         []UpstreamInfo       `json:"upstreams"`
	Bootstrap         core.BootstrapConfig `json:"bootstrap"`
	ConditionalRoutes map[string]string    `json:"conditionalRoutes,omitempty"`
	EnableEDE         bool                 `json:"enableEDE"`
	BlockUnqualified  bool                 `json:"blockUnqualified"`
	BlockPrivatePTR   bool                 `json:"blockPrivatePTR"`
	BlockIPv6         bool                 `json:"blockIPv6"`
	BlockECH          bool                 `json:"blockECH"`
	EDNSPadding       int                  `json:"ednsPadding"`
	BlockANY          bool                 `json:"blockANY"`
	BlockANYMode      string               `json:"blockANYMode"`
}

// TakeoverStatus 物理网卡接管运行状态
type TakeoverStatus struct {
	Active   bool                    `json:"active"`
	Adapters []platform.AdapterState `json:"adapters"`
}

// MetricsStatus 性能与统计指标
type MetricsStatus struct {
	TotalQueries   uint64  `json:"totalQueries"`
	SuccessQueries uint64  `json:"successQueries"`
	FailedQueries  uint64  `json:"failedQueries"`
	AvgLatencyMs   float64 `json:"avgLatencyMs"`
	QPS            float64 `json:"qps"`
}

// StatusResponse GET /api/v1/status 响应载荷
type StatusResponse struct {
	Version       string                   `json:"version"`
	PID           int                      `json:"pid"`
	UptimeSeconds int64                    `json:"uptimeSeconds"`
	DNS           DNSStatus                `json:"dns"`
	Takeover      TakeoverStatus           `json:"takeover"`
	Metrics       MetricsStatus            `json:"metrics"`
	Cache         core.CacheStats          `json:"cache"`
	Filter        core.FilterStats         `json:"filter"`
	Hosts         core.HostsConfig         `json:"hosts"`
	Rebind        core.RebindConfig        `json:"rebind"`
	Access        core.AccessControlConfig `json:"access"`
	RateLimit     core.RateLimitConfig     `json:"rateLimit"`
	DNS64         core.DNS64Config         `json:"dns64"`
	Rewrite       core.RewriteConfig       `json:"rewrite"`
	Zone          core.ZoneConfig          `json:"zone"`
	SafeSearch    core.SafeSearchConfig    `json:"safeSearch"`
	SafeBrowsing  core.SafeBrowsingConfig  `json:"safeBrowsing"`
	ECS           core.ECSConfig           `json:"ecs"`
	Clients       []core.ClientInfo        `json:"clients,omitempty"`
}

// Event WebSocket 事件推送载荷
type Event struct {
	Type      string `json:"type"`      // "query", "metrics", "takeover", "dns", "alert"
	Timestamp int64  `json:"timestamp"` // Unix 毫秒时间戳
	Data      any    `json:"data"`
}

// QueryEventData 单次 DNS 请求事件详情
type QueryEventData struct {
	Domain       string  `json:"domain"`
	QType        string  `json:"qtype"`
	ClientIP     string  `json:"clientIP"`
	ClientName   string  `json:"clientName,omitempty"`
	DurationMs   float64 `json:"durationMs"`
	Success      bool    `json:"success"`
	RCode        string  `json:"rcode,omitempty"`
	CacheHit     string  `json:"cacheHit,omitempty"`
	Blocked      bool    `json:"blocked"`
	FilterRule   string  `json:"filterRule,omitempty"`
	FilterReason string  `json:"filterReason,omitempty"`
	ErrorMessage string  `json:"errorMessage,omitempty"`
}

// CacheEntriesResponse 缓存条目列表响应
type CacheEntriesResponse struct {
	Total   int                   `json:"total"`
	Entries []core.CacheEntryItem `json:"entries"`
}

// QueryStatsResponse 查询统计中心聚合响应（24h 滚动窗口）
type QueryStatsResponse struct {
	Summary    querylog.Summary     `json:"summary"`
	PerHour    []querylog.HourPoint `json:"perHour"`
	TopDomains []querylog.NameCount `json:"topDomains"`
	TopBlocked []querylog.NameCount `json:"topBlocked"`
	TopClients []querylog.NameCount `json:"topClients"`
}

// FilterListsResponse 订阅规则列表响应
type FilterListsResponse struct {
	Total int               `json:"total"`
	Lists []core.FilterList `json:"lists"`
}

// FilterRulesResponse 自定义规则文本响应
type FilterRulesResponse struct {
	Rules []string `json:"rules"`
}

// FilterActionRequest 单项规则操作请求
type FilterActionRequest struct {
	ID string `json:"id"`
}

// ConfigureUpstreamRequest 定义见 ./types_upstream.go（含独立回退链字段）

// ConfigureBootstrapRequest 单独配置 Bootstrap 引导 DNS 请求
type ConfigureBootstrapRequest struct {
	Enabled *bool                  `json:"enabled,omitempty"`
	Servers []core.BootstrapServer `json:"servers"`
}

// TestUpstreamRequest 测试单个上游延迟请求
type TestUpstreamRequest struct {
	Protocol string `json:"protocol"`
	Server   string `json:"server"`
	URL      string `json:"url"`
}

// TestUpstreamResponse 测试单个上游延迟响应
type TestUpstreamResponse struct {
	Success   bool    `json:"success"`
	LatencyMs float64 `json:"latencyMs"`
	Error     string  `json:"error,omitempty"`
}

// EmergencyRestoreResponse 应急恢复结果
type EmergencyRestoreResponse struct {
	// Healed 为 true 表示确实改回了系统 DNS；false 表示原本就是干净的。
	Healed  bool   `json:"healed"`
	Message string `json:"message"`
}

// AdapterTakeoverRequest 单个网卡接管/还原请求
type AdapterTakeoverRequest struct {
	AdapterID string `json:"adapterId"`
	Enable    bool   `json:"enable"`
}

// LANStatusResponse 局域网 DNS 服务状态响应
type LANStatusResponse struct {
	AllowLAN        bool     `json:"allowLAN"`
	ListenAddresses []string `json:"listenAddresses"`
	LANAddresses    []string `json:"lanAddresses"`
	FirewallAllowed bool     `json:"firewallAllowed"`
	// FirewallBackend 为探测到的防火墙后端；"none" 表示未检测到任何管理器、
	// 端口本就对外开放，无需放行规则。
	FirewallBackend string `json:"firewallBackend"`
}

// ConfigureLANRequest 配置局域网 DNS 请求
type ConfigureLANRequest struct {
	AllowLAN          bool `json:"allowLAN"`
	ConfigureFirewall bool `json:"configureFirewall,omitempty"`
}

// ConfigureFirewallRequest 配置防火墙请求
type ConfigureFirewallRequest struct {
	Enable bool `json:"enable"`
}

// MetaResponse 描述宿主机运行平台信息（免鉴权，供 Web 控制台平台自适应）。
type MetaResponse struct {
	OS string `json:"os"` // 运行平台标识：windows / linux
}

// AuthStatusResponse 描述当前认证与 Web 服务概况
type AuthStatusResponse struct {
	Initialized         bool   `json:"initialized"`
	WebEnabled          bool   `json:"webEnabled"`
	Authenticated       bool   `json:"authenticated"`
	Username            string `json:"username"`
	Locked              bool   `json:"locked"`
	LockoutRemainingSec int64  `json:"lockoutRemainingSec"`
}

// LoginRequest 登录请求载荷
type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// LoginResponse 登录成功响应载荷
type LoginResponse struct {
	Token     string `json:"token"`
	Username  string `json:"username"`
	ExpiresAt int64  `json:"expiresAt"`
}

// SetupAuthRequest 首次初始化管理员账号密码
type SetupAuthRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// ChangePasswordRequest 修改密码请求
type ChangePasswordRequest struct {
	Username    string `json:"username"`
	OldPassword string `json:"oldPassword,omitempty"`
	NewPassword string `json:"newPassword"`
}

// WebStatusResponse 局域网 Web 管理服务状态响应
type WebStatusResponse struct {
	Enabled         bool     `json:"enabled"`
	Port            int      `json:"port"`
	ListenAddress   string   `json:"listenAddress"`
	LANAddresses    []string `json:"lanAddresses"`
	WebURLs         []string `json:"webUrls"`
	FirewallAllowed bool     `json:"firewallAllowed"`
	// FirewallBackend 为探测到的防火墙后端；"none" 表示未检测到任何管理器、
	// 端口本就对外开放，无需放行规则。
	FirewallBackend string `json:"firewallBackend"`
	Initialized     bool   `json:"initialized"`
	Username        string `json:"username"`
}

// ConfigureWebRequest 配置局域网 Web 管理服务
type ConfigureWebRequest struct {
	Enabled           bool `json:"enabled"`
	Port              int  `json:"port,omitempty"`
	ConfigureFirewall bool `json:"configureFirewall,omitempty"`
}

// AutofixPortRequest 端口冲突自动修复请求
type AutofixPortRequest struct {
	StartDNS bool `json:"startDNS,omitempty"` // 修复成功后是否立即拉起 DNS 监听器
}

// LoginBackgroundResponse 获取全局登录背景配置响应
type LoginBackgroundResponse struct {
	Type      string `json:"type"`      // 类型: "none" | "url" | "custom"
	URL       string `json:"url"`       // 外部网络图片 URL 或服务端本地图片接口相对路径
	Opacity   int    `json:"opacity"`   // 遮罩暗度 0 - 100
	Blur      int    `json:"blur"`      // 毛玻璃模糊 0 - 20 px
	UpdatedAt int64  `json:"updatedAt"` // 最近配置更新时间戳
}

// SetLoginBackgroundRequest 设置全局登录背景请求
type SetLoginBackgroundRequest struct {
	Type          string `json:"type,omitempty"`          // 可选类型指定
	URL           string `json:"url"`                     // 外部图片 URL 或 "data:image/..." Base64 编码，为空表示清除
	Opacity       int    `json:"opacity"`                 // 遮罩暗度 0 - 100
	Blur          int    `json:"blur"`                    // 毛玻璃模糊 0 - 20 px
	AdminPassword string `json:"adminPassword,omitempty"` // 远程未登录客户端鉴权密码（可选）
}

// ConfigureAccessRequest 客户端访问控制配置请求
type ConfigureAccessRequest struct {
	AllowedClients []string `json:"allowedClients"`
	BlockedClients []string `json:"blockedClients"`
}

// ConfigureRateLimitRequest 客户端限流配置请求
type ConfigureRateLimitRequest struct {
	Enabled    bool     `json:"enabled"`
	Rate       float64  `json:"rate"`
	Burst      int      `json:"burst"`
	IPv4Prefix int      `json:"ipv4Prefix"`
	IPv6Prefix int      `json:"ipv6Prefix"`
	ExemptIPs  []string `json:"exemptIPs"`
}

// ConfigureDNS64Request DNS64 IPv6 过渡合成配置请求
type ConfigureDNS64Request struct {
	Enabled  bool     `json:"enabled"`
	Prefixes []string `json:"prefixes"`
}

// ConfigureBlockUnqualifiedRequest 单标签域名外泄阻断配置请求
type ConfigureBlockUnqualifiedRequest struct {
	BlockUnqualified bool `json:"blockUnqualified"`
}

// ConfigureRewriteRequest DNS 重写整体配置请求
type ConfigureRewriteRequest struct {
	Enabled *bool               `json:"enabled,omitempty"`
	TTL     *uint32             `json:"ttl,omitempty"`
	Rules   *[]core.RewriteRule `json:"rules,omitempty"`
}

// ConfigureECSRequest EDNS Client Subnet 策略配置请求
type ConfigureECSRequest struct {
	Enabled      *bool   `json:"enabled,omitempty"`
	StripECS     *bool   `json:"stripECS,omitempty"`
	CustomSubnet *string `json:"customSubnet,omitempty"`
}

// ConfigureSafeSearchRequest 强制安全搜索配置请求
type ConfigureSafeSearchRequest struct {
	Enabled  *bool     `json:"enabled,omitempty"`
	Disabled *[]string `json:"disabled,omitempty"`
	TTL      *uint32   `json:"ttl,omitempty"`
}

// SafeSearchConfigResponse 强制安全搜索配置响应（含当前有效配置）
type SafeSearchConfigResponse struct {
	Enabled  bool     `json:"enabled"`
	Disabled []string `json:"disabled"`
	TTL      uint32   `json:"ttl"`
}

// ConfigureClientAliasRequest 客户端友好主机名别名配置请求
type ConfigureClientAliasRequest struct {
	IP   string `json:"ip"`
	Name string `json:"name"`
}

// ConfigurePrivacyRequest 隐私保护与协议增强策略配置请求
type ConfigurePrivacyRequest struct {
	EnableEDE       *bool `json:"enableEDE,omitempty"`
	BlockPrivatePTR *bool `json:"blockPrivatePTR,omitempty"`
	BlockIPv6       *bool `json:"blockIPv6,omitempty"`
	BlockECH        *bool `json:"blockECH,omitempty"`
	EDNSPadding     *int  `json:"ednsPadding,omitempty"`
	// BlockANY 对 ANY 查询返回最小化应答（RFC 8482）
	BlockANY *bool `json:"blockANY,omitempty"`
	// BlockANYMode 最小化应答形式："notimp"（默认）或 "rfc8482"
	BlockANYMode *string `json:"blockANYMode,omitempty"`
}

// ConfigureRebindRequest DNS Rebinding 攻击防御配置请求
type ConfigureRebindRequest struct {
	Enabled        *bool    `json:"enabled,omitempty"`
	AllowedDomains []string `json:"allowedDomains,omitempty"`
}

// ConfigureHostsRequest 本地 Hosts 解析器配置请求
type ConfigureHostsRequest struct {
	Enabled       *bool    `json:"enabled,omitempty"`
	UseSystemHost *bool    `json:"useSystemHost,omitempty"`
	CustomFiles   []string `json:"customFiles,omitempty"`
	TTL           *uint32  `json:"ttl,omitempty"`
}

// ScheduleConfigResponse 分时拦截（时间计划）配置与实时生效状态
type ScheduleConfigResponse struct {
	Enabled   bool                    `json:"enabled"`
	Schedules []core.BlockingSchedule `json:"schedules"`
	Active    bool                    `json:"active"`   // 当前时刻拦截是否生效
	ActiveID  string                  `json:"activeId"` // 当前命中的计划 ID（无则空）
}

// ConfigureScheduleRequest 分时拦截配置请求
type ConfigureScheduleRequest struct {
	Enabled   *bool                    `json:"enabled,omitempty"`
	Schedules *[]core.BlockingSchedule `json:"schedules,omitempty"`
}

// FilterPauseRequest 定时暂停拦截请求
type FilterPauseRequest struct {
	// Paused 为 true 时按 DurationSec 暂停（0 表示暂停至手动恢复）；为 false 时立即恢复。
	Paused      bool  `json:"paused"`
	DurationSec int64 `json:"durationSec,omitempty"`
}

// FilterPauseResponse 定时暂停拦截状态响应
type FilterPauseResponse struct {
	Paused bool `json:"paused"`
	// RemainingSeconds 暂停剩余秒数（未暂停为 0）
	RemainingSeconds int64 `json:"remainingSeconds"`
	// PausedUntilMs 预计恢复时刻 Unix 毫秒（未暂停为 0）
	PausedUntilMs int64 `json:"pausedUntilMs"`
	// BlockingEnabled 过滤总开关（与暂停态解耦，供前端区分「已关闭」与「已暂停」）
	BlockingEnabled bool `json:"blockingEnabled"`
}

// ClientGroupConfigResponse 客户端分组配置与已解析规则集选项。
//
// 具体字段定义见 ./types_client_groups.go。


// ConfigureClientGroupsRequest 客户端分组配置请求
type ConfigureClientGroupsRequest struct {
	Enabled *bool               `json:"enabled,omitempty"`
	Groups  *[]core.ClientGroup `json:"groups,omitempty"`
}
