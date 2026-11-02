package main

import (
	"context"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// GetBlockedServices 返回内置阻断服务目录与当前选择状态
func (p *program) GetBlockedServices(ctx context.Context) (*ipc.BlockedServicesResponse, error) {
	services, groups := core.ServicesCatalog()

	p.mu.Lock()
	selectedIDs := append([]string(nil), p.cfg.Filter.BlockedServices...)
	selectedGroups := append([]string(nil), p.cfg.Filter.BlockedServiceGroups...)
	schedules := copyServiceSchedules(p.cfg.Filter.ServiceSchedules)
	var states []core.ServiceScheduleState
	if p.filterEngine != nil {
		states = p.filterEngine.ServiceScheduleStates()
	}
	p.mu.Unlock()

	if states == nil {
		states = []core.ServiceScheduleState{}
	}

	return &ipc.BlockedServicesResponse{
		Services:       services,
		Groups:         groups,
		BlockedIDs:     selectedIDs,
		BlockedGroups:  selectedGroups,
		ActiveRules:    core.CountBlockedServiceRules(selectedIDs, selectedGroups),
		Schedules:      schedules,
		ScheduleStates: states,
	}, nil
}

// copyServiceSchedules 深拷贝计划表，避免把引擎内部切片交给调用方改动
func copyServiceSchedules(src map[string][]core.BlockingSchedule) map[string][]core.BlockingSchedule {
	if len(src) == 0 {
		return map[string][]core.BlockingSchedule{}
	}
	out := make(map[string][]core.BlockingSchedule, len(src))
	for id, schedules := range src {
		out[id] = append([]core.BlockingSchedule(nil), schedules...)
	}
	return out
}

// ConfigureBlockedServices 更新内置服务拦截选择并热重载规则索引
func (p *program) ConfigureBlockedServices(ctx context.Context, req ipc.ConfigureBlockedServicesRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.Filter
	if req.IDs != nil {
		cfg.BlockedServices = *req.IDs
	}
	if req.Groups != nil {
		cfg.BlockedServiceGroups = *req.Groups
	}
	if req.Schedules != nil {
		cfg.ServiceSchedules = *req.Schedules
	}
	// 归一化会剔除目录中不存在的 ID，因此未启用规则引擎时也要走一遍，
	// 免得把非法勾选原样写进配置文件
	core.NormalizeFilterConfig(&cfg)

	if p.filterEngine != nil {
		if err := p.filterEngine.UpdateConfig(cfg); err != nil {
			return err
		}
		// 引擎内部会把归一化后的配置存回自身，配置文件需要跟随同一份结果
		p.cfg.Filter = p.filterEngine.GetConfig()
	} else {
		p.cfg.Filter = cfg
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化内置服务拦截配置失败: %v\n", err)
		}
	}
	return nil
}
