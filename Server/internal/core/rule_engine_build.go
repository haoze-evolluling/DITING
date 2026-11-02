package core

import (
	"bytes"
	"log"
	"os"
	"path/filepath"
	"time"
)

// ruleSet 一次规则索引构建所用的三类规则源。
//
// 分开保存而非合成一个切片：客户端分组需要按来源挑选（自定义规则恒包含、
// 订阅列表按组过滤、内置服务规则恒包含），合并后就无法区分。
type ruleSet struct {
	custom  []*ParsedRule
	service []*ParsedRule
	lists   []*ParsedRule
}

// all 返回参与全局索引的全部规则，顺序即优先级：自定义 → 内置服务 → 订阅列表。
func (rs ruleSet) all() []*ParsedRule {
	out := make([]*ParsedRule, 0, len(rs.custom)+len(rs.service)+len(rs.lists))
	out = append(out, rs.custom...)
	out = append(out, rs.service...)
	out = append(out, rs.lists...)
	return out
}

// rebuildUnlocked 从自定义规则、内置服务规则与订阅缓存重建匹配器并原子切换
func (e *RuleEngine) rebuildUnlocked() error {
	rs := e.loadAllRulesUnlocked()
	allRules := rs.all()

	// 构建新的匹配器实例并全量原子切换
	newMatcher := NewRuleMatcher()
	newMatcher.BuildFromRules(allRules)
	e.matcher = newMatcher

	// 按客户端分组构建专属匹配器（组数有限，内存可控）
	e.compileGroupMatchersUnlocked(rs.custom, rs.service, rs.lists)

	log.Printf("[RuleEngine] 规则索引构建完毕，共激活 %d 条规则", len(allRules))
	return nil
}

// loadAllRulesUnlocked 解析自定义规则、内置服务规则与各启用订阅列表的缓存。
//
// 自定义规则优先级最高，其次是被整组拦截的内置服务，
// 最后才按列表声明顺序排列订阅规则。
func (e *RuleEngine) loadAllRulesUnlocked() ruleSet {
	rs := ruleSet{}

	for _, line := range e.cfg.CustomRules {
		if r, ok := ParseRuleLine(line, "custom"); ok && r != nil {
			rs.custom = append(rs.custom, r)
		}
	}

	rs.service = parseBlockedServiceRules(e.cfg.BlockedServices, e.cfg.BlockedServiceGroups)

	for i := range e.cfg.Lists {
		list := &e.cfg.Lists[i]
		if !list.Enabled {
			continue
		}
		cacheFile := filepath.Join(e.cfg.DataDir, list.ID+".txt")
		data, err := os.ReadFile(cacheFile)
		if err != nil {
			continue
		}
		parsed, err := ParseRules(bytes.NewReader(data), list.ID)
		if err != nil {
			continue
		}
		list.RulesCount = len(parsed)
		rs.lists = append(rs.lists, parsed...)
	}
	return rs
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
				changed := false
				for _, l := range e.cfg.Lists {
					if l.Enabled && time.Since(time.UnixMilli(l.LastUpdated)) > interval {
						if updated, err := e.refreshListUnlocked(l.ID); err == nil && updated {
							changed = true
						}
					}
				}
				if changed {
					_ = e.rebuildUnlocked()
				}
			}
			e.mu.Unlock()
		}
	}
}

// Close 关闭规则引擎后台协程
func (e *RuleEngine) Close() {
	close(e.stopCh)
}
