package ipc

import "github.com/haoze-evolluling/diting/server/internal/core"

// ClientGroupConfigResponse 客户端分组配置与可绑定项。
type ClientGroupConfigResponse struct {
	Enabled bool               `json:"enabled"`
	Groups  []core.ClientGroup `json:"groups"`
	// RuleLists 供前端多选绑定的可用订阅列表（ID + 名称）
	RuleLists []ClientGroupRuleListOption `json:"ruleLists"`
	// Upstreams 供前端多选绑定的可用上游节点。
	// 分组只能指向主链路中真实存在的节点，否则绑定后无法生效。
	Upstreams []ClientGroupUpstreamOption `json:"upstreams"`
}

// ClientGroupRuleListOption 分组可绑定的订阅列表选项
type ClientGroupRuleListOption struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Enabled bool   `json:"enabled"`
}

// ClientGroupUpstreamOption 分组可绑定的上游节点选项
type ClientGroupUpstreamOption struct {
	ID       string `json:"id"`
	Protocol string `json:"protocol"`
	Server   string `json:"server"`
}
