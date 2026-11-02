package main

import (
	"context"
	"fmt"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// GetSafeSearch 获取当前强制安全搜索配置
func (p *program) GetSafeSearch(ctx context.Context) (*ipc.SafeSearchConfigResponse, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.SafeSearch
	if p.safeSearchEng != nil {
		cfg = p.safeSearchEng.GetConfig()
	}
	disabled := cfg.Disabled
	if disabled == nil {
		disabled = []string{}
	}
	return &ipc.SafeSearchConfigResponse{Enabled: cfg.Enabled, Disabled: disabled, TTL: cfg.TTL}, nil
}

// ConfigureSafeSearch 更新强制安全搜索配置并持久化
func (p *program) ConfigureSafeSearch(ctx context.Context, req ipc.ConfigureSafeSearchRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.SafeSearch
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	if req.Disabled != nil {
		cfg.Disabled = filterSafeSearchServices(*req.Disabled)
	}
	// 显式提交非正 TTL 是非法输入而非「未提供」（见 ConfigureRewrite 同型说明）
	if req.TTL != nil {
		if *req.TTL <= 0 {
			return fmt.Errorf("TTL 必须为正整数")
		}
		cfg.TTL = *req.TTL
	}

	if p.safeSearchEng != nil {
		p.safeSearchEng.Configure(cfg)
	}

	p.cfg.SafeSearch = cfg
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 SafeSearch 配置失败: %v\n", err)
		}
	}
	return nil
}

// filterSafeSearchServices 过滤非法服务商标识并去重
func filterSafeSearchServices(list []string) []string {
	valid := make(map[string]bool)
	for _, s := range core.SafeSearchServices() {
		valid[s] = true
	}
	seen := make(map[string]bool)
	out := make([]string, 0, len(list))
	for _, s := range list {
		if !valid[s] || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}
