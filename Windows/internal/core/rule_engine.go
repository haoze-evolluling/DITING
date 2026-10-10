package core

import (
	"bytes"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"
)

// RuleEngine 谛听 Windows 规则过滤与拦截引擎核心
type RuleEngine struct {
	mu             sync.RWMutex
	cfg            FilterConfig
	matcher        *RuleMatcher
	totalQueries   atomic.Uint64
	blockedQueries atomic.Uint64
	allowedQueries atomic.Uint64

	httpClient *http.Client
	stopCh     chan struct{}
}

// NewRuleEngine 初始化规则引擎并自动加载构建规则索引
func NewRuleEngine(cfg FilterConfig) *RuleEngine {
	NormalizeFilterConfig(&cfg)

	engine := &RuleEngine{
		cfg:     cfg,
		matcher: NewRuleMatcher(),
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		stopCh: make(chan struct{}),
	}

	// 确保规则缓存目录存在
	if err := os.MkdirAll(cfg.DataDir, 0755); err != nil {
		log.Printf("[RuleEngine] 创建缓存目录失败 (%s): %v", cfg.DataDir, err)
	}

	// 首次全量加载规则
	if err := engine.rebuildUnlocked(); err != nil {
		log.Printf("[RuleEngine] 初始加载规则出现警告: %v", err)
	}

	// 启动定期更新定时器
	go engine.runUpdateTicker()

	return engine
}

// IsEnabled 查询规则过滤总开关
func (e *RuleEngine) IsEnabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.cfg.Enabled
}

// SetEnabled 设置规则过滤总开关
func (e *RuleEngine) SetEnabled(enabled bool) {
	e.mu.Lock()
	e.cfg.Enabled = enabled
	e.mu.Unlock()
}

// GetConfig 获取当前过滤配置副本
func (e *RuleEngine) GetConfig() FilterConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.cfg
}

// UpdateConfig 更新过滤配置并热重载
func (e *RuleEngine) UpdateConfig(cfg FilterConfig) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	// 保持未显式更新字段
	if cfg.CustomRules == nil {
		cfg.CustomRules = e.cfg.CustomRules
	}
	if cfg.Lists == nil {
		cfg.Lists = e.cfg.Lists
	}
	if cfg.DataDir == "" {
		cfg.DataDir = e.cfg.DataDir
	}
	NormalizeFilterConfig(&cfg)

	// 若仅切换了 Enabled 状态，无需全量从磁盘重构
	onlyEnabledChanged := (e.cfg.Enabled != cfg.Enabled &&
		e.cfg.BlockMode == cfg.BlockMode &&
		e.cfg.BlockingIPv4 == cfg.BlockingIPv4 &&
		e.cfg.BlockingIPv6 == cfg.BlockingIPv6 &&
		e.cfg.UpdateIntervalHours == cfg.UpdateIntervalHours &&
		len(e.cfg.CustomRules) == len(cfg.CustomRules) &&
		len(e.cfg.Lists) == len(cfg.Lists))

	e.cfg = cfg
	if onlyEnabledChanged && e.matcher != nil && e.matcher.TotalRules() > 0 {
		return nil
	}

	return e.rebuildUnlocked()
}

func (e *RuleEngine) getMatcher() *RuleMatcher {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.matcher
}

// GetStats 获取当前运行时拦截与规则统计指标
func (e *RuleEngine) GetStats() FilterStats {
	e.mu.RLock()
	defer e.mu.RUnlock()

	total := e.totalQueries.Load()
	blocked := e.blockedQueries.Load()
	allowed := e.allowedQueries.Load()
	var rate float64
	if total > 0 {
		rate = float64(blocked) / float64(total) * 100
	}

	activeLists := 0
	for _, l := range e.cfg.Lists {
		if l.Enabled {
			activeLists++
		}
	}

	totalRules := 0
	if e.matcher != nil {
		totalRules = e.matcher.TotalRules()
	}

	return FilterStats{
		Enabled:        e.cfg.Enabled,
		TotalRules:     totalRules,
		ActiveLists:    activeLists,
		TotalQueries:   total,
		BlockedQueries: blocked,
		AllowedQueries: allowed,
		BlockRate:      rate,
	}
}

// Match 对域名进行过滤评估并记录遥测统计
func (e *RuleEngine) Match(domain string, qtype uint16) CheckHostResult {
	if !e.IsEnabled() {
		return CheckHostResult{Action: "pass"}
	}

	matcher := e.getMatcher()
	if matcher == nil {
		return CheckHostResult{Action: "pass"}
	}

	e.totalQueries.Add(1)
	res := matcher.Match(domain, qtype)

	if res.Blocked {
		e.blockedQueries.Add(1)
	} else if res.Action == "allow" {
		e.allowedQueries.Add(1)
	}

	return res
}

// CheckHost 提供外部纯只读检测（不增加正式查询指标计数）
func (e *RuleEngine) CheckHost(domain string, qtype uint16) CheckHostResult {
	matcher := e.getMatcher()
	if matcher == nil {
		return CheckHostResult{Action: "pass"}
	}
	return matcher.Match(domain, qtype)
}

// rebuildUnlocked 从自定义规则与订阅缓存重建匹配器并原子切换
func (e *RuleEngine) rebuildUnlocked() error {
	var allRules []*ParsedRule

	// 1. 解析用户自定义规则 (最高优先级)
	for _, line := range e.cfg.CustomRules {
		if r, ok := ParseRuleLine(line, "custom"); ok && r != nil {
			allRules = append(allRules, r)
		}
	}

	// 2. 加载各启用订阅列表的缓存文件
	for i := range e.cfg.Lists {
		list := &e.cfg.Lists[i]
		if !list.Enabled {
			continue
		}
		cacheFile := filepath.Join(e.cfg.DataDir, list.ID+".txt")
		if data, err := os.ReadFile(cacheFile); err == nil {
			listRules, err := ParseRules(bytes.NewReader(data), list.ID)
			if err == nil {
				list.RulesCount = len(listRules)
				allRules = append(allRules, listRules...)
			}
		}
	}

	// 3. 构建新的匹配器实例并全量原子切换
	newMatcher := NewRuleMatcher()
	newMatcher.BuildFromRules(allRules)
	e.matcher = newMatcher

	log.Printf("[RuleEngine] 规则索引构建完毕，共激活 %d 条规则", len(allRules))
	return nil
}

func (e *RuleEngine) runUpdateTicker() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-e.stopCh:
			return
		case <-ticker.C:
			e.mu.Lock()
			interval := time.Duration(e.cfg.UpdateIntervalHours) * time.Hour
			needUpdate := false
			for _, l := range e.cfg.Lists {
				if l.Enabled && time.Since(time.UnixMilli(l.LastUpdated)) > interval {
					needUpdate = true
					break
				}
			}
			if needUpdate {
				for _, l := range e.cfg.Lists {
					if l.Enabled && time.Since(time.UnixMilli(l.LastUpdated)) > interval {
						_ = e.refreshListUnlocked(l.ID)
					}
				}
				_ = e.rebuildUnlocked()
			}
			e.mu.Unlock()
		}
	}
}

// Close 关闭规则引擎后台协程
func (e *RuleEngine) Close() {
	close(e.stopCh)
}
