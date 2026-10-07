package main

import (
	"context"
	"fmt"

	"github.com/haoze-evolluling/diting/windows/internal/config"
	"github.com/haoze-evolluling/diting/windows/internal/core"
)

// GetFilterStats 实现 ServiceController 接口
func (p *program) GetFilterStats(ctx context.Context) (*core.FilterStats, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return &core.FilterStats{Enabled: false}, nil
	}
	st := p.filterEngine.GetStats()
	return &st, nil
}

// GetFilterConfig 实现 ServiceController 接口
func (p *program) GetFilterConfig(ctx context.Context) (*core.FilterConfig, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		cfg := core.DefaultFilterConfig()
		return &cfg, nil
	}
	cfg := p.filterEngine.GetConfig()
	return &cfg, nil
}

// UpdateFilterConfig 实现 ServiceController 接口
func (p *program) UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	if err := p.filterEngine.UpdateConfig(cfg); err != nil {
		return err
	}
	p.cfg.Filter = p.filterEngine.GetConfig()
	_ = config.SaveConfig(p.configPath, p.cfg)
	return nil
}

// GetFilterLists 实现 ServiceController 接口
func (p *program) GetFilterLists(ctx context.Context) ([]core.FilterList, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return []core.FilterList{}, nil
	}
	return p.filterEngine.GetFilterLists(), nil
}

// AddFilterList 实现 ServiceController 接口
func (p *program) AddFilterList(ctx context.Context, list core.FilterList) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	if err := p.filterEngine.AddFilterList(list); err != nil {
		return err
	}
	p.cfg.Filter = p.filterEngine.GetConfig()
	_ = config.SaveConfig(p.configPath, p.cfg)
	return nil
}

// UpdateFilterList 实现 ServiceController 接口
func (p *program) UpdateFilterList(ctx context.Context, list core.FilterList) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	if err := p.filterEngine.UpdateFilterList(list); err != nil {
		return err
	}
	p.cfg.Filter = p.filterEngine.GetConfig()
	_ = config.SaveConfig(p.configPath, p.cfg)
	return nil
}

// DeleteFilterList 实现 ServiceController 接口
func (p *program) DeleteFilterList(ctx context.Context, id string) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	if err := p.filterEngine.RemoveFilterList(id); err != nil {
		return err
	}
	p.cfg.Filter = p.filterEngine.GetConfig()
	_ = config.SaveConfig(p.configPath, p.cfg)
	return nil
}

// RefreshFilterLists 实现 ServiceController 接口
func (p *program) RefreshFilterLists(ctx context.Context, id string) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	var err error
	if id != "" {
		err = p.filterEngine.RefreshList(id)
	} else {
		err = p.filterEngine.RefreshAllLists()
	}
	if err != nil {
		return err
	}
	p.cfg.Filter = p.filterEngine.GetConfig()
	_ = config.SaveConfig(p.configPath, p.cfg)
	return nil
}

// GetCustomRules 实现 ServiceController 接口
func (p *program) GetCustomRules(ctx context.Context) ([]string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return []string{}, nil
	}
	return p.filterEngine.GetCustomRules(), nil
}

// SetCustomRules 实现 ServiceController 接口
func (p *program) SetCustomRules(ctx context.Context, rules []string) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return fmt.Errorf("规则过滤引擎未初始化")
	}

	if err := p.filterEngine.SetCustomRules(rules); err != nil {
		return err
	}
	p.cfg.Filter = p.filterEngine.GetConfig()
	_ = config.SaveConfig(p.configPath, p.cfg)
	return nil
}

// CheckHostRule 实现 ServiceController 接口
func (p *program) CheckHostRule(ctx context.Context, domain string, qtype uint16) (*core.CheckHostResult, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.filterEngine == nil {
		return &core.CheckHostResult{Action: "pass"}, nil
	}
	res := p.filterEngine.CheckHost(domain, qtype)
	return &res, nil
}
