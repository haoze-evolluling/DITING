package windows

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// DefaultStateFileName 默认持久化文件名
const DefaultStateFileName = "dns_state.json"

// AdapterState 记录接管前单个网卡的原始配置
type AdapterState struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Index       int      `json:"index"`
	Description string   `json:"description"`
	IPv4DHCP    bool     `json:"ipv4DHCP"`
	IPv6DHCP    bool     `json:"ipv6DHCP"`
	IPv4DNS     []string `json:"ipv4DNS"`
	IPv6DNS     []string `json:"ipv6DNS"`
}

// TakeoverState 整体 DNS 接管持久化状态
type TakeoverState struct {
	Active    bool           `json:"active"`
	Version   string         `json:"version"`
	PID       int            `json:"pid"`
	Timestamp time.Time      `json:"timestamp"`
	Adapters  []AdapterState `json:"adapters"`
}

// Restorer 抽象网卡还原能力接口，便于解耦自愈逻辑与执行逻辑
type Restorer interface {
	RestoreAdapters(ctx context.Context, adapters []AdapterState) error
}

// StateStore 定义状态存取接口
type StateStore interface {
	Save(state *TakeoverState) error
	Load() (*TakeoverState, error)
	Clear() error
	GetFilePath() string
	CheckAndSelfHeal(ctx context.Context, restorer Restorer) (bool, error)
}

// FileStateStore 基于 JSON 文件的状态持久化存储实现
type FileStateStore struct {
	mu       sync.Mutex
	filePath string
}

// GetDefaultStateFilePath 返回标准状态文件路径 (%ProgramData%\DITING\dns_state.json)
func GetDefaultStateFilePath() string {
	programData := os.Getenv("ProgramData")
	if programData == "" {
		programData = `C:\ProgramData`
	}
	return filepath.Join(programData, "DITING", DefaultStateFileName)
}

// NewFileStateStore 创建状态持久化实例
func NewFileStateStore(filePath string) *FileStateStore {
	if filePath == "" {
		filePath = GetDefaultStateFilePath()
	}
	return &FileStateStore{filePath: filePath}
}

// GetFilePath 获取当前持久化文件绝对路径
func (s *FileStateStore) GetFilePath() string {
	return s.filePath
}

// Save 原子写入状态文件（先写临时文件后重命名，防止写入中断导致文件损坏）
func (s *FileStateStore) Save(state *TakeoverState) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	dir := filepath.Dir(s.filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("创建状态目录失败: %w", err)
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化接管状态失败: %w", err)
	}

	tmpFile := s.filePath + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0644); err != nil {
		return fmt.Errorf("写入临时状态文件失败: %w", err)
	}

	// Windows 下 os.Rename 目标文件存在时会替换（Go 1.5+）
	// 为防锁冲突，先尝试删除目标文件
	_ = os.Remove(s.filePath)
	if err := os.Rename(tmpFile, s.filePath); err != nil {
		_ = os.Remove(tmpFile)
		return fmt.Errorf("重命名替换状态文件失败: %w", err)
	}

	return nil
}

// Load 读取持久化状态，若文件不存在则返回 nil, nil
func (s *FileStateStore) Load() (*TakeoverState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.filePath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, fmt.Errorf("读取状态文件失败: %w", err)
	}

	var state TakeoverState
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("反序列化状态文件失败: %w", err)
	}

	return &state, nil
}

// Clear 清理状态文件
func (s *FileStateStore) Clear() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.Remove(s.filePath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("清理状态文件失败: %w", err)
	}
	return nil
}

// CheckAndSelfHeal 在服务启动时检查是否存在未正常还原的残留接管配置并自动执行自愈还原
func (s *FileStateStore) CheckAndSelfHeal(ctx context.Context, restorer Restorer) (bool, error) {
	state, err := s.Load()
	if err != nil {
		return false, fmt.Errorf("检查自愈状态时读取文件失败: %w", err)
	}

	if state == nil || !state.Active || len(state.Adapters) == 0 {
		return false, nil
	}

	// 发现残留的活跃接管状态，触发自愈还原
	if restorer != nil {
		if err := restorer.RestoreAdapters(ctx, state.Adapters); err != nil {
			return false, fmt.Errorf("自愈还原网卡 DNS 失败: %w", err)
		}
	}

	// 还原成功后清除状态文件
	_ = s.Clear()
	return true, nil
}
