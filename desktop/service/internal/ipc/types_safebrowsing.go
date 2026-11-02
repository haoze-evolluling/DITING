package ipc

import "github.com/haoze-evolluling/diting/server/internal/core"

// SafeBrowsingResponse 恶意网址库与家长控制的配置与运行统计
type SafeBrowsingResponse struct {
	Config core.SafeBrowsingConfig `json:"config"`
	Stats  core.SafeBrowsingStats  `json:"stats"`
	// BlockingIPv4 / BlockingIPv6 当前用于构造阻断应答的地址，
	// 供界面说明「命中后会得到什么」，与规则拦截保持同一套策略
	BlockingIPv4 string `json:"blockingIPv4"`
	BlockingIPv6 string `json:"blockingIPv6"`
	BlockMode    string `json:"blockMode"`
}

// ConfigureSafeBrowsingRequest 更新声誉查询配置。
//
// 四个字段均为可选：省略表示沿用当前值。用指针是为了让「关闭」与
// 「未表态」在传输层就分得开——布尔零值无法承担这个区分。
type ConfigureSafeBrowsingRequest struct {
	Enabled         *bool `json:"enabled,omitempty"`
	ParentalEnabled *bool `json:"parentalEnabled,omitempty"`
	TimeoutMs       *int  `json:"timeoutMs,omitempty"`
	CacheSize       *int  `json:"cacheSize,omitempty"`
	CacheTTLSeconds *int  `json:"cacheTTLSeconds,omitempty"`
}
