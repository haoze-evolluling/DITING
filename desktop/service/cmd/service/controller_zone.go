package main

import (
	"context"
	"fmt"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// GetZoneConfig 返回本地权威区配置与各区的构建结果
func (p *program) GetZoneConfig(ctx context.Context) (*ipc.ZoneConfigResponse, error) {
	p.mu.Lock()
	cfg := copyZoneConfig(p.cfg.Zone)
	var states []core.ZoneState
	recordCount := 0
	if p.zoneEngine != nil {
		states = p.zoneEngine.States()
		recordCount = p.zoneEngine.RecordCount()
	}
	p.mu.Unlock()

	if states == nil {
		states = []core.ZoneState{}
	}

	return &ipc.ZoneConfigResponse{
		Enabled:     cfg.Enabled,
		TTL:         cfg.TTL,
		Zones:       cfg.Zones,
		States:      states,
		RecordCount: recordCount,
		MaxZones:    core.MaxZoneCount,
		MaxRecords:  core.MaxZoneRecords,
	}, nil
}

// copyZoneConfig 深拷贝区配置，避免把内部切片交给调用方改动
func copyZoneConfig(src core.ZoneConfig) core.ZoneConfig {
	out := src
	out.Zones = append([]core.ZoneEntry(nil), src.Zones...)
	return out
}

// ConfigureZone 更新本地权威区配置并重建索引
func (p *program) ConfigureZone(ctx context.Context, req ipc.ConfigureZoneRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.Zone
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	// 显式提交非正 TTL 是非法输入而非「未提供」（见 ConfigureRewrite 同型说明）
	if req.TTL != nil {
		if *req.TTL <= 0 {
			return fmt.Errorf("TTL 必须为正整数")
		}
		cfg.TTL = *req.TTL
	}
	if req.Zones != nil {
		cfg.Zones = *req.Zones
	}
	// 归一化补齐空的区 ID：没有稳定 ID 时前端无法为每一行维护展开状态
	core.NormalizeZoneConfig(&cfg)

	if p.zoneEngine != nil {
		p.zoneEngine.Configure(cfg)
	}
	p.cfg.Zone = cfg

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化本地权威区配置失败: %v\n", err)
		}
	}
	return nil
}
