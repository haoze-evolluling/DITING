package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/platform"
	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

var (
	storeMu sync.Mutex
)

// init 向 platform 注册「从配置文件读取接管状态路径」的读取器。
//
// 应急恢复通道（`-restore` / GUI）可能不带 -config，需要按默认配置路径
// 反查服务实际使用的 stateFilePath，否则自定义路径的部署会读错文件。
func init() {
	platform.RegisterStatePathReader(func(configPath string) (string, error) {
		cfg, err := LoadConfig(configPath)
		if err != nil || cfg == nil {
			return "", err
		}
		return cfg.Takeover.StateFilePath, nil
	})
}

// DefaultConfigFileName 默认配置文件名称
const DefaultConfigFileName = "config.json"

// GetDefaultConfigPath 获取默认配置文件路径。
//
// Windows: %ProgramData%\DITING\config.json；Linux: /etc/diting/config.json
// （非 root 时退避至 ~/.diting/config.json）。设置 DITING_DATA_DIR 时收敛至该目录。
func GetDefaultConfigPath() string {
	return platform.DefaultConfigPath()
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
	if cfg.DNS.EDNSPadding < 0 {
		cfg.DNS.EDNSPadding = 0
	}
	// 未知模式回落到默认值：一个拼错的模式名不该让 ANY 查询完全不被处理
	switch cfg.DNS.BlockANYMode {
	case ANYModeNotImp, ANYModeRFC8482:
	default:
		cfg.DNS.BlockANYMode = ANYModeNotImp
	}
	if cfg.IPC.ListenAddress == "" {
		cfg.IPC.ListenAddress = "127.0.0.1:15353"
	}
	if cfg.Upstream.Mode == "" {
		cfg.Upstream.Mode = core.ModePrimaryBackup
	}
	if cfg.Upstream.EDNSPadding < 0 {
		cfg.Upstream.EDNSPadding = 0
	}
	if len(cfg.Upstream.Bootstrap.Servers) == 0 && cfg.Upstream.Bootstrap.Enabled {
		cfg.Upstream.Bootstrap.Servers = []core.BootstrapServer{
			{ID: "bs-ali", Name: "AliDNS", Address: "223.5.5.5:53", Weight: 1.0},
			{ID: "bs-dnspod", Name: "DNSPod", Address: "119.29.29.29:53", Weight: 1.0},
		}
	}
	if cfg.Web.ListenPort <= 0 {
		cfg.Web.ListenPort = 15353
	}
	if cfg.Web.Background.Opacity <= 0 && cfg.Web.Background.Type == "" {
		cfg.Web.Background.Opacity = 40
	}
	if cfg.Web.Background.Opacity < 0 {
		cfg.Web.Background.Opacity = 0
	} else if cfg.Web.Background.Opacity > 100 {
		cfg.Web.Background.Opacity = 100
	}
	if cfg.Web.Background.Blur < 0 {
		cfg.Web.Background.Blur = 0
	} else if cfg.Web.Background.Blur > 20 {
		cfg.Web.Background.Blur = 20
	}
	core.NormalizeCacheConfig(&cfg.Cache)
	core.NormalizeFilterConfig(&cfg.Filter)
	core.NormalizeRewriteConfig(&cfg.Rewrite)
	core.NormalizeZoneConfig(&cfg.Zone)
	core.NormalizeSafeSearchConfig(&cfg.SafeSearch)
	core.NormalizeSafeBrowsingConfig(&cfg.SafeBrowsing)
	core.NormalizeEncryptedDNSConfig(&cfg.Encrypted)
	_ = cfg.Client.Normalize()
	querylog.NormalizeQueryLogConfig(&cfg.QueryLog)
}
