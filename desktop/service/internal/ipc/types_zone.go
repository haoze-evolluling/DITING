package ipc

import "github.com/haoze-evolluling/diting/server/internal/core"

// ZoneConfigResponse 本地权威区配置与各区的构建结果
type ZoneConfigResponse struct {
	Enabled bool             `json:"enabled"`
	TTL     uint32           `json:"ttl"`
	Zones   []core.ZoneEntry `json:"zones"`
	// States 各区的解析结果，含未加载原因，供界面逐区标注
	States []core.ZoneState `json:"states"`
	// RecordCount 已加载的名字总数
	RecordCount int `json:"recordCount"`
	// MaxZones / MaxRecords 上限，供界面提前提示而非事后报错
	MaxZones   int `json:"maxZones"`
	MaxRecords int `json:"maxRecords"`
}

// ConfigureZoneRequest 更新本地权威区配置。
//
// 三个字段均为可选：省略表示沿用当前值；Zones 传空数组表示清空全部区。
// 用指针区分「未提供」与「提供空值」两种意图。
type ConfigureZoneRequest struct {
	Enabled *bool             `json:"enabled,omitempty"`
	TTL     *uint32           `json:"ttl,omitempty"`
	Zones   *[]core.ZoneEntry `json:"zones,omitempty"`
}

// ZoneTestRequest 保存前的区文本解析自检
type ZoneTestRequest struct {
	Origin  string `json:"origin"`
	Content string `json:"content"`
	TTL     uint32 `json:"ttl,omitempty"`
}

// ZoneTestResponse 自检结果：成功时给出逐条记录预览
type ZoneTestResponse struct {
	Success bool     `json:"success"`
	Records []string `json:"records"`
	Error   string   `json:"error,omitempty"`
}
