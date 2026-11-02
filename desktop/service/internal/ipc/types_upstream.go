package ipc

import "github.com/haoze-evolluling/diting/server/internal/core"

// ConfigureUpstreamRequest 动态配置上游请求。
//
// 回退相关字段集中在独立文件中，避免 types.go 随功能增长触碰 600 行上限。
type ConfigureUpstreamRequest struct {
	Mode              string                `json:"mode"`
	Providers         []core.ProviderConfig `json:"providers"`
	Bootstrap         *core.BootstrapConfig `json:"bootstrap,omitempty"`
	ConditionalRoutes map[string]string     `json:"conditionalRoutes,omitempty"`

	// FallbackProviders 为独立回退链。
	//
	// nil 表示"保持现状"，非 nil（含空切片）表示替换；传空切片即关闭回退。
	FallbackProviders []core.ProviderConfig `json:"fallbackProviders,omitempty"`
	// FallbackTimeoutMs 为主链路独立超时（毫秒）；0 表示采用服务端默认值。
	FallbackTimeoutMs *int `json:"fallbackTimeoutMs,omitempty"`
	// FallbackOnRcode 指定触发回退的响应码；nil 表示保持现状，空切片表示恢复默认。
	FallbackOnRcode *[]int `json:"fallbackOnRcode,omitempty"`
	// FallbackOnError 控制传输层故障是否触发回退。
	FallbackOnError *bool `json:"fallbackOnError,omitempty"`
}
