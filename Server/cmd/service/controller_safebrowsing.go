package main

import (
	"context"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// GetSafeBrowsing 返回声誉查询配置与累计统计
func (p *program) GetSafeBrowsing(ctx context.Context) (*ipc.SafeBrowsingResponse, error) {
	p.mu.Lock()
	cfg := p.cfg.SafeBrowsing
	filterCfg := p.cfg.Filter
	var stats core.SafeBrowsingStats
	if p.safeBrowsing != nil {
		stats = p.safeBrowsing.Stats()
	}
	p.mu.Unlock()

	// 阻断应答沿用规则拦截的全局策略：用户在「拦截方式」里选的形式
	// 对声誉拦截同样有效，否则同一个域名会因拦截来源不同而给出不同结果
	return &ipc.SafeBrowsingResponse{
		Config:       cfg,
		Stats:        stats,
		BlockingIPv4: filterCfg.BlockingIPv4,
		BlockingIPv6: filterCfg.BlockingIPv6,
		BlockMode:    filterCfg.BlockMode,
	}, nil
}

// ConfigureSafeBrowsing 更新声誉查询配置
func (p *program) ConfigureSafeBrowsing(ctx context.Context, req ipc.ConfigureSafeBrowsingRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.SafeBrowsing
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	if req.ParentalEnabled != nil {
		cfg.ParentalEnabled = *req.ParentalEnabled
	}
	if req.TimeoutMs != nil {
		cfg.TimeoutMs = *req.TimeoutMs
	}
	if req.CacheSize != nil {
		cfg.CacheSize = *req.CacheSize
	}
	if req.CacheTTLSeconds != nil {
		cfg.CacheTTLSeconds = *req.CacheTTLSeconds
	}
	// 归一化会改写越界参数，配置里必须存归一化后的结果，
	// 否则重启后读回的是界面填过的那个非法值
	core.NormalizeSafeBrowsingConfig(&cfg)

	if p.safeBrowsing != nil {
		p.safeBrowsing.Configure(cfg)
	}
	p.cfg.SafeBrowsing = cfg

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化声誉查询配置失败: %v\n", err)
		}
	}
	return nil
}
