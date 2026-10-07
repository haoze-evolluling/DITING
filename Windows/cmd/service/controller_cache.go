package main

import (
	"context"
	"fmt"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/ipc"
)

// GetCacheStats 实现 ServiceController 接口
func (p *program) GetCacheStats(ctx context.Context) (*core.CacheStats, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		return &core.CacheStats{Enabled: false}, nil
	}
	st := p.cache.Stats()
	return &st, nil
}

// GetCacheEntries 实现 ServiceController 接口
func (p *program) GetCacheEntries(ctx context.Context, query string, limit int) (*ipc.CacheEntriesResponse, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		return &ipc.CacheEntriesResponse{Total: 0, Entries: []core.CacheEntryItem{}}, nil
	}
	total, entries := p.cache.GetEntries(query, limit)
	return &ipc.CacheEntriesResponse{
		Total:   total,
		Entries: entries,
	}, nil
}

// GetCacheTopDomains 实现 ServiceController 接口
func (p *program) GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		return []core.CacheDomainStat{}, nil
	}
	return p.cache.GetTopDomains(limit), nil
}

// ClearCache 实现 ServiceController 接口
func (p *program) ClearCache(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		return fmt.Errorf("智能缓存尚未初始化")
	}
	p.cache.Clear()
	return nil
}

// GetCacheConfig 实现 ServiceController 接口
func (p *program) GetCacheConfig(ctx context.Context) (*core.CacheConfig, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		cfg := p.cfg.Cache
		return &cfg, nil
	}
	cfg := p.cache.GetConfig()
	return &cfg, nil
}

// UpdateCacheConfig 实现 ServiceController 接口
func (p *program) UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	core.NormalizeCacheConfig(&cfg)
	if p.cache != nil {
		p.cache.UpdateConfig(cfg)
	}
	p.cfg.Cache = cfg
	return nil
}
