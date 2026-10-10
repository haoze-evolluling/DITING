package core

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
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
	return e.refreshListUnlocked(list.ID)
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
	return e.refreshListUnlocked(id)
}

// RefreshAllLists 强制更新所有启用的订阅列表
func (e *RuleEngine) RefreshAllLists() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	for _, l := range e.cfg.Lists {
		if l.Enabled {
			_ = e.refreshListUnlocked(l.ID)
		}
	}
	return e.rebuildUnlocked()
}

func (e *RuleEngine) refreshListUnlocked(id string) error {
	var target *FilterList
	for i := range e.cfg.Lists {
		if e.cfg.Lists[i].ID == id {
			target = &e.cfg.Lists[i]
			break
		}
	}
	if target == nil {
		return fmt.Errorf("找不到订阅列表: %s", id)
	}

	data, err := e.fetchListContent(target.URL)
	if err != nil {
		return fmt.Errorf("获取规则源失败 (%s): %w", target.URL, err)
	}

	cacheFile := filepath.Join(e.cfg.DataDir, target.ID+".txt")
	if err := os.WriteFile(cacheFile, data, 0644); err != nil {
		return fmt.Errorf("保存规则缓存文件失败: %w", err)
	}

	// 计算规则数与校验和
	rules, _ := ParseRules(bytes.NewReader(data), target.ID)
	hash := sha256.Sum256(data)
	target.RulesCount = len(rules)
	target.LastUpdated = time.Now().UnixMilli()
	target.Checksum = hex.EncodeToString(hash[:])

	return e.rebuildUnlocked()
}

func (e *RuleEngine) fetchListContent(urlStr string) ([]byte, error) {
	if strings.HasPrefix(urlStr, "http://") || strings.HasPrefix(urlStr, "https://") {
		req, err := http.NewRequest(http.MethodGet, urlStr, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", "DITING-DNS-Engine/1.0")

		resp, err := e.httpClient.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("HTTP 状态码异常: %d", resp.StatusCode)
		}
		return io.ReadAll(io.LimitReader(resp.Body, 50*1024*1024))
	}

	// 本地文件读取
	return os.ReadFile(urlStr)
}
