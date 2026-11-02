package main

import (
	"context"
	"fmt"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

// queryLogRef 在锁内取出查询日志引用，避免在 querylog 自有锁之外再持有 program 锁
func (p *program) queryLogRef() *querylog.QueryLog {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.queryLog
}

// GetQueryLog 实现 ServiceController 接口
func (p *program) GetQueryLog(ctx context.Context, query querylog.SearchQuery) (*querylog.SearchResult, error) {
	ql := p.queryLogRef()
	if ql == nil {
		return &querylog.SearchResult{Entries: []querylog.Record{}}, nil
	}
	res := ql.Search(query)
	if res.Entries == nil {
		res.Entries = []querylog.Record{}
	}
	return &res, nil
}

// GetQueryStats 实现 ServiceController 接口
func (p *program) GetQueryStats(ctx context.Context) (*ipc.QueryStatsResponse, error) {
	ql := p.queryLogRef()
	if ql == nil {
		return &ipc.QueryStatsResponse{
			PerHour:    []querylog.HourPoint{},
			TopDomains: []querylog.NameCount{},
			TopBlocked: []querylog.NameCount{},
			TopClients: []querylog.NameCount{},
		}, nil
	}
	const topN = 10
	return &ipc.QueryStatsResponse{
		Summary:    ql.Stats(),
		PerHour:    ql.PerHour(),
		TopDomains: ql.TopDomains(topN),
		TopBlocked: ql.TopBlockedDomains(topN),
		TopClients: ql.TopClients(topN),
	}, nil
}

// ClearQueryLog 实现 ServiceController 接口
func (p *program) ClearQueryLog(ctx context.Context) error {
	ql := p.queryLogRef()
	if ql == nil {
		return fmt.Errorf("查询日志尚未初始化")
	}
	return ql.Clear(true)
}

// GetQueryLogConfig 实现 ServiceController 接口
func (p *program) GetQueryLogConfig(ctx context.Context) (*querylog.QueryLogConfig, error) {
	ql := p.queryLogRef()
	if ql != nil {
		cfg := ql.Config()
		return &cfg, nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	cfg := p.cfg.QueryLog
	return &cfg, nil
}

// UpdateQueryLogConfig 实现 ServiceController 接口
func (p *program) UpdateQueryLogConfig(ctx context.Context, cfg querylog.QueryLogConfig) error {
	ql := p.queryLogRef()
	if ql != nil {
		if err := ql.UpdateConfig(cfg); err != nil {
			return err
		}
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	p.cfg.QueryLog = cfg
	if p.configPath != "" && p.cfg != nil {
		_ = config.SaveConfig(p.configPath, p.cfg)
	}
	return nil
}
