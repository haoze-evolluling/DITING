package core

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// GetCustomRules 获取用户自定义规则列表
func (e *RuleEngine) GetCustomRules() []string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	rules := make([]string, len(e.cfg.CustomRules))
	copy(rules, e.cfg.CustomRules)
	return rules
}

// SetCustomRules 更新用户自定义规则并热重构
func (e *RuleEngine) SetCustomRules(rules []string) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.cfg.CustomRules = rules
	return e.rebuildUnlocked()
}

// GetFilterLists 获取订阅规则列表
func (e *RuleEngine) GetFilterLists() []FilterList {
	e.mu.RLock()
	defer e.mu.RUnlock()
	lists := make([]FilterList, len(e.cfg.Lists))
	copy(lists, e.cfg.Lists)
	return lists
}

// AddFilterList 添加新订阅源并触发加载
func (e *RuleEngine) AddFilterList(list FilterList) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if list.ID == "" {
		list.ID = fmt.Sprintf("list-%d", time.Now().UnixNano())
	}
	for _, existing := range e.cfg.Lists {
		if existing.ID == list.ID {
			return fmt.Errorf("订阅列表 ID 已存在: %s", list.ID)
		}
	}

	e.cfg.Lists = append(e.cfg.Lists, list)
	if _, err := e.refreshListUnlocked(list.ID); err != nil {
		return err
	}
	return e.rebuildUnlocked()
}

// UpdateFilterList 更新已存在的订阅源
func (e *RuleEngine) UpdateFilterList(list FilterList) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	idx := -1
	for i, existing := range e.cfg.Lists {
		if existing.ID == list.ID {
			idx = i
			break
		}
	}
	if idx == -1 {
		return fmt.Errorf("找不到订阅列表: %s", list.ID)
	}

	// 引擎侧同样拒收空 URL：控制器与引擎都可被直接调用，
	// 只在 HTTP 入口加闸会让其他调用方仍能清空在用订阅源。
	if strings.TrimSpace(list.URL) == "" {
		return fmt.Errorf("订阅列表 %s 的 URL 不能为空", list.ID)
	}

	e.cfg.Lists[idx].Name = list.Name
	e.cfg.Lists[idx].URL = list.URL
	e.cfg.Lists[idx].Enabled = list.Enabled

	return e.rebuildUnlocked()
}

// RemoveFilterList 移除指定订阅源
func (e *RuleEngine) RemoveFilterList(id string) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	idx := -1
	for i, existing := range e.cfg.Lists {
		if existing.ID == id {
			idx = i
			break
		}
	}
	if idx == -1 {
		return fmt.Errorf("找不到订阅列表: %s", id)
	}

	e.cfg.Lists = append(e.cfg.Lists[:idx], e.cfg.Lists[idx+1:]...)
	// 清理缓存文件
	cachePath := filepath.Join(e.cfg.DataDir, id+".txt")
	_ = os.Remove(cachePath)

	return e.rebuildUnlocked()
}

// RefreshList 强制拉取指定规则源并重建匹配器
func (e *RuleEngine) RefreshList(id string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if _, err := e.refreshListUnlocked(id); err != nil {
		return err
	}
	return e.rebuildUnlocked()
}

// RefreshAllLists 强制更新所有启用的订阅列表
func (e *RuleEngine) RefreshAllLists() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	changed := false
	for _, l := range e.cfg.Lists {
		if !l.Enabled {
			continue
		}
		if updated, err := e.refreshListUnlocked(l.ID); err == nil && updated {
			changed = true
		}
	}
	// 无内容变化（全部 304 或沿用缓存）时跳过重建，避免无谓的索引重构
	if !changed {
		return nil
	}
	return e.rebuildUnlocked()
}

// refreshListUnlocked 拉取单个规则源，返回内容是否发生变化（需要重建索引）。
//
// 借鉴 blocky downloaded_cache 的增量刷新语义：
//   - 304 → 仅刷新时间戳，不重解析不重建；
//   - 200 → .tmp + rename 原子写盘并标记 ok；
//   - 传输类错误且本地已有可用缓存 → 保留旧规则并标记 cached（刷新失败不再清零规则）；
//   - HTTP 4xx/5xx 或首次拉取失败 → 标记 failed 并上报错误。
func (e *RuleEngine) refreshListUnlocked(id string) (bool, error) {
	var target *FilterList
	for i := range e.cfg.Lists {
		if e.cfg.Lists[i].ID == id {
			target = &e.cfg.Lists[i]
			break
		}
	}
	if target == nil {
		return false, fmt.Errorf("找不到订阅列表: %s", id)
	}

	res, err := e.fetchListContentConditional(target.URL, target.ETag, target.LastModified)
	if err != nil {
		if _, ok := readListCache(e.cfg.DataDir, target.ID); ok && isTransientFetchError(err) {
			target.LastStatus = ListStatusCached
			target.LastError = err.Error()
			log.Printf("[RuleEngine] 规则源拉取失败，沿用本地缓存 (%s): %v", target.URL, err)
			return false, nil
		}
		target.LastStatus = ListStatusFailed
		target.LastError = err.Error()
		return false, fmt.Errorf("获取规则源失败 (%s): %w", target.URL, err)
	}

	if res.notModified {
		target.LastStatus = ListStatusUnchanged
		target.LastError = ""
		target.LastUpdated = time.Now().UnixMilli()
		return false, nil
	}

	if err := writeListCacheAtomic(e.cfg.DataDir, target.ID, res.data); err != nil {
		target.LastStatus = ListStatusFailed
		target.LastError = err.Error()
		return false, fmt.Errorf("保存规则缓存文件失败: %w", err)
	}

	// 计算规则数并记录协商凭证
	rules, _ := ParseRules(bytes.NewReader(res.data), target.ID)
	target.RulesCount = len(rules)
	target.LastUpdated = time.Now().UnixMilli()
	target.Checksum = listChecksum(res.data)
	target.ETag = res.etag
	target.LastModified = res.lastModified
	target.LastStatus = ListStatusOK
	target.LastError = ""

	return true, nil
}
