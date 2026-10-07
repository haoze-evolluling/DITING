package ipc

import (
	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// Response 通用 API JSON 响应体
type Response[T any] struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
	Data    T      `json:"data,omitempty"`
	Error   string `json:"error,omitempty"`
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
	Running         bool           `json:"running"`
	ListenAddresses []string       `json:"listenAddresses"`
	Mode            string         `json:"mode"`
	Upstreams       []UpstreamInfo `json:"upstreams"`
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
	Metrics       MetricsStatus   `json:"metrics"`
	Cache         core.CacheStats `json:"cache"`
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
	ErrorMessage string  `json:"errorMessage,omitempty"`
}

// CacheEntriesResponse 缓存条目列表响应
type CacheEntriesResponse struct {
	Total   int                   `json:"total"`
	Entries []core.CacheEntryItem `json:"entries"`
}

// ConfigureUpstreamRequest 动态配置上游请求
type ConfigureUpstreamRequest struct {
	Mode      string                `json:"mode"`
	Providers []core.ProviderConfig `json:"providers"`
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

