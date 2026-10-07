package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

var (
	storeMu sync.Mutex
)

// DefaultConfigFileName 默认配置文件名称
const DefaultConfigFileName = "config.json"

// GetDefaultConfigPath 获取默认配置文件路径 (%ProgramData%\DITING\config.json)
func GetDefaultConfigPath() string {
	programData := os.Getenv("ProgramData")
	if programData == "" {
		programData = `C:\ProgramData`
	}
	return filepath.Join(programData, "DITING", DefaultConfigFileName)
}

// LoadConfig 从指定路径加载配置，若路径为空则使用默认路径，若文件不存在则返回默认配置
func LoadConfig(path string) (*Config, error) {
	storeMu.Lock()
	defer storeMu.Unlock()

	if path == "" {
		path = GetDefaultConfigPath()
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return DefaultConfig(), nil
		}
		return nil, fmt.Errorf("读取配置文件失败 (%s): %w", path, err)
	}

	cfg := DefaultConfig()
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("反序列化配置文件失败 (%s): %w", path, err)
	}

	// 填充关键默认值（防空防护）
	normalizeConfig(cfg)
	return cfg, nil
}

// SaveConfig 原子保存配置到文件
func SaveConfig(path string, cfg *Config) error {
	storeMu.Lock()
	defer storeMu.Unlock()

	if path == "" {
		path = GetDefaultConfigPath()
	}
	if cfg == nil {
		cfg = DefaultConfig()
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("创建配置目录失败: %w", err)
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %w", err)
	}

	tmpFile := path + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0644); err != nil {
		return fmt.Errorf("写入临时配置文件失败: %w", err)
	}

	_ = os.Remove(path)
	if err := os.Rename(tmpFile, path); err != nil {
		_ = os.Remove(tmpFile)
		return fmt.Errorf("替换配置文件失败: %w", err)
	}

	return nil
}

// normalizeConfig 规范化配置并补齐缺失默认项
func normalizeConfig(cfg *Config) {
	if len(cfg.DNS.UDPAddresses) == 0 && len(cfg.DNS.TCPAddresses) == 0 {
		cfg.DNS.UDPAddresses = []string{"127.0.0.1:53", "[::1]:53"}
		cfg.DNS.TCPAddresses = []string{"127.0.0.1:53", "[::1]:53"}
	}
	if cfg.DNS.ReadTimeout <= 0 {
		cfg.DNS.ReadTimeout = 5 * time.Second
	}
	if cfg.DNS.WriteTimeout <= 0 {
		cfg.DNS.WriteTimeout = 5 * time.Second
	}
	if cfg.IPC.ListenAddress == "" {
		cfg.IPC.ListenAddress = "127.0.0.1:15353"
	}
	if cfg.Upstream.Mode == "" {
		cfg.Upstream.Mode = core.ModePrimaryBackup
	}
	core.NormalizeCacheConfig(&cfg.Cache)
}
