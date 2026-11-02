package main

import (
	"context"
	"fmt"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// GetClientGroups 返回当前客户端分组配置与可选订阅列表
func (p *program) GetClientGroups(ctx context.Context) (*ipc.ClientGroupConfigResponse, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.Client.GroupConfig()
	res := &ipc.ClientGroupConfigResponse{
		Enabled:   cfg.Enabled,
		Groups:    cfg.Groups,
		RuleLists: p.clientGroupRuleListOptions(),
		Upstreams: p.clientGroupUpstreamOptions(),
	}
	if res.Groups == nil {
		res.Groups = []core.ClientGroup{}
	}
	return res, nil
}

// clientGroupUpstreamOptions 汇总可供分组绑定的上游节点（调用方需持有 p.mu）
func (p *program) clientGroupUpstreamOptions() []ipc.ClientGroupUpstreamOption {
	opts := []ipc.ClientGroupUpstreamOption{}
	if p.cfg == nil {
		return opts
	}
	for _, prov := range p.cfg.Upstream.Providers {
		addr := prov.Server
		if addr == "" {
			addr = prov.URL
		}
		opts = append(opts, ipc.ClientGroupUpstreamOption{
			ID:       prov.ID,
			Protocol: string(core.ParseProtocol(string(prov.Protocol))),
			Server:   addr,
		})
	}
	return opts
}

// clientGroupRuleListOptions 汇总可供分组绑定的订阅列表（调用方需持有 p.mu）
func (p *program) clientGroupRuleListOptions() []ipc.ClientGroupRuleListOption {
	opts := []ipc.ClientGroupRuleListOption{}
	if p.filterEngine == nil {
		return opts
	}
	for _, l := range p.filterEngine.GetFilterLists() {
		opts = append(opts, ipc.ClientGroupRuleListOption{ID: l.ID, Name: l.Name, Enabled: l.Enabled})
	}
	return opts
}

// ConfigureClientGroups 更新客户端分组配置并热生效
func (p *program) ConfigureClientGroups(ctx context.Context, req ipc.ConfigureClientGroupsRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	cfg := p.cfg.Client.GroupConfig()
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	if req.Groups != nil {
		cfg.Groups = *req.Groups
	}
	if err := core.NormalizeClientGroupConfig(&cfg); err != nil {
		log.Printf("[Clients] 客户端分组配置归一化提示: %v\n", err)
	}

	// 1. 热更新规则引擎的分组匹配器
	if err := p.filterEngine.SetClientGroups(cfg); err != nil {
		return err
	}

	// 2. 重建 IP→分组解析器（DNS 热路径使用）
	if gr, err := core.NewGroupResolver(cfg); err == nil {
		p.groupResolver = gr
	} else {
		log.Printf("[Clients] 重建客户端分组匹配器警告: %v\n", err)
	}

	// 3. 重新绑定分组专属上游：分组增删或上游改动都会让旧的分派表失效
	p.applyGroupUpstreams(cfg)

	// 4. 同步持久化配置
	p.cfg.Client.GroupsEnabled = cfg.Enabled
	p.cfg.Client.Groups = cfg.Groups
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化客户端分组配置失败: %v\n", err)
		}
	}
	return nil
}

// applyGroupUpstreams 把分组配置中的专属上游绑定到解析器（调用方需持有 p.mu）。
//
// 分组配置与上游列表是两份独立持久化的配置，两侧的中间状态都可能出现；
// 因此这里只记录警告而不让调用失败，避免一次不一致导致整个分组配置无法保存。
func (p *program) applyGroupUpstreams(cfg core.ClientGroupConfig) {
	if p.resolver == nil {
		return
	}
	if err := p.resolver.SetGroupUpstreams(cfg.GroupUpstreamMap()); err != nil {
		log.Printf("[Clients] 分组专属上游绑定提示: %v\n", err)
	}
}
