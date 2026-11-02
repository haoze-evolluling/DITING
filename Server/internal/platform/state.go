package platform

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// FileStateStore 基于 JSON 文件的状态持久化存储实现。
//
// 该实现完全平台无关：原子写入（先写临时文件后重命名）与崩溃自愈流程
// 在 Windows 与 Linux 上语义一致，仅默认文件路径由 DefaultStateFilePath 决定。
type FileStateStore struct {
	mu       sync.Mutex
	filePath string
}

// NewFileStateStore 创建状态持久化实例；path 为空时使用平台默认路径。
func NewFileStateStore(path string) *FileStateStore {
	if path == "" {
		path = DefaultStateFilePath()
	}
	return &FileStateStore{filePath: path}
}

// GetFilePath 获取当前持久化文件绝对路径。
func (s *FileStateStore) GetFilePath() string {
	return s.filePath
}

// Save 原子写入状态文件（先写临时文件后重命名，防止写入中断导致文件损坏）。
func (s *FileStateStore) Save(state *TakeoverState) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	dir := filepath.Dir(s.filePath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("创建状态目录失败: %w", err)
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化接管状态失败: %w", err)
	}

	tmpFile := s.filePath + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0o644); err != nil {
		return fmt.Errorf("写入临时状态文件失败: %w", err)
	}

	// Windows 下 os.Rename 目标文件存在时会替换（Go 1.5+）；Linux 同样原子替换。
	// 为兼容特定文件系统与防锁冲突，先尝试删除目标文件。
	_ = os.Remove(s.filePath)
	if err := os.Rename(tmpFile, s.filePath); err != nil {
		_ = os.Remove(tmpFile)
		return fmt.Errorf("重命名替换状态文件失败: %w", err)
	}

	return nil
}

// Load 读取持久化状态，若文件不存在则返回 nil, nil。
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

// Clear 清理状态文件。
func (s *FileStateStore) Clear() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.Remove(s.filePath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("清理状态文件失败: %w", err)
	}
	return nil
}

// CheckAndSelfHeal 在服务启动时检查是否存在未正常还原的残留接管配置并自动执行自愈还原。
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
	if err := s.Clear(); err != nil {
		return false, fmt.Errorf("清理残留接管状态失败: %w", err)
	}
	return true, nil
}
