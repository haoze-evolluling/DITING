package main

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// cachePersistPath 解析生效的缓存落盘路径（调用方需持有 p.mu）
func (p *program) cachePersistPath() string {
	if p.cfg != nil && strings.TrimSpace(p.cfg.Cache.PersistPath) != "" {
		return p.cfg.Cache.PersistPath
	}
	return core.CachePersistPath(platform.DefaultDataDir())
}

// restoreCacheFromDisk 启动时按配置恢复缓存
func (p *program) restoreCacheFromDisk() {
	if p.cache == nil || p.cfg == nil || !p.cfg.Cache.PersistEnabled {
		return
	}

	// 路径在配置中留空时补上平台约定值，使落盘与恢复指向同一文件
	if strings.TrimSpace(p.cfg.Cache.PersistPath) == "" {
		p.cfg.Cache.PersistPath = p.cachePersistPath()
	}

	path := p.cachePersistPath()
	n, err := p.cache.LoadFromFile(path)
	if err != nil {
		// 载入失败不阻断启动：缓存是纯性能设施，冷启动只是慢一点
		log.Printf("[Cache] 恢复缓存失败，将以空缓存启动: %v\n", err)
		return
	}
	if n > 0 {
		log.Printf("[Cache] 已从 %s 恢复 %d 条缓存条目\n", path, n)
	}
	p.cache.StartPersistLoop()
}

// cachePersistSnapshot 汇总落盘与排除规则的当前状态（调用方需持有 p.mu）
//
// 三个对外方法共用同一份快照：若各自拼装字段，界面在「落盘」之后刷新状态时
// 会因为响应里缺少排除规则而把统计显示成 0。
func (p *program) cachePersistSnapshot() *ipc.CachePersistResponse {
	res := &ipc.CachePersistResponse{Path: p.cachePersistPath()}
	if p.cache != nil {
		res.EntryCount = p.cache.Stats().EntryCount
		res.LastError = p.cache.LastPersistError()
		res.ExcludeRules = p.cache.Excluder().Patterns()
		res.ExcludeHits = p.cache.Excluder().Hits()
	}
	if p.cfg != nil {
		res.PersistOn = p.cfg.Cache.PersistEnabled
		res.IntervalSec = p.cfg.Cache.PersistIntervalSeconds
	}
	return res
}

// DumpCache 把当前缓存显式落盘
func (p *program) DumpCache(ctx context.Context) (*ipc.CachePersistResponse, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		return nil, fmt.Errorf("缓存未初始化")
	}
	if err := p.cache.SaveToFile(p.cachePersistPath()); err != nil {
		return nil, err
	}
	return p.cachePersistSnapshot(), nil
}

// LoadCache 从落盘文件恢复缓存并合并进当前实例
func (p *program) LoadCache(ctx context.Context) (*ipc.CachePersistResponse, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cache == nil {
		return nil, fmt.Errorf("缓存未初始化")
	}
	n, err := p.cache.LoadFromFile(p.cachePersistPath())
	if err != nil {
		return nil, err
	}
	res := p.cachePersistSnapshot()
	res.Restored = n
	return res, nil
}

// CachePersistStatus 返回落盘状态概览
func (p *program) CachePersistStatus(ctx context.Context) (*ipc.CachePersistResponse, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.cachePersistSnapshot(), nil
}
