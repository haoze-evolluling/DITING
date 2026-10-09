package ipc

import (
	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// Response 通用 API JSON 响应体
type Response[T any] struct {
	Success  bool                     `json:"success"`
	Message  string                   `json:"message,omitempty"`
	Data     T                        `json:"data,omitempty"`
	Error    string                   `json:"error,omitempty"`
	Conflict *windows.PortCheckResult `json:"conflict,omitempty"`
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
}

// DNSStatus DNS 监听器运行状态
type DNSStatus struct {
	Running         bool                 `json:"running"`
	ListenAddresses []string             `json:"listenAddresses"`
	AllowLAN        bool                 `json:"allowLAN"`
	LANAddresses    []string             `json:"lanAddresses,omitempty"`
	Mode            string               `json:"mode"`
	Upstreams       []UpstreamInfo       `json:"upstreams"`
	Bootstrap       core.BootstrapConfig `json:"bootstrap"`
}

// TakeoverStatus 物理网卡接管运行状态
type TakeoverStatus struct {
	Active   bool                   `json:"active"`
	Adapters []windows.AdapterState `json:"adapters"`
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
	Version       string          `json:"version"`
	PID           int             `json:"pid"`
	UptimeSeconds int64           `json:"uptimeSeconds"`
	DNS           DNSStatus       `json:"dns"`
	Takeover      TakeoverStatus  `json:"takeover"`
	Metrics       MetricsStatus    `json:"metrics"`
	Cache         core.CacheStats  `json:"cache"`
	Filter        core.FilterStats `json:"filter"`
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

// ConfigureUpstreamRequest 动态配置上游请求
type ConfigureUpstreamRequest struct {
	Mode      string                `json:"mode"`
	Providers []core.ProviderConfig `json:"providers"`
	Bootstrap *core.BootstrapConfig `json:"bootstrap,omitempty"`
}

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
	Initialized     bool     `json:"initialized"`
	Username        string   `json:"username"`
}

// ConfigureWebRequest 配置局域网 Web 管理服务
type ConfigureWebRequest struct {
	Enabled           bool `json:"enabled"`
	Port              int  `json:"port,omitempty"`
	ConfigureFirewall bool `json:"configureFirewall,omitempty"`
}



