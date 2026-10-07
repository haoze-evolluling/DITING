package config

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

// DNSConfig 本地 DNS 监听服务配置
type DNSConfig struct {
	UDPAddresses []string      `json:"udpAddresses"`
	TCPAddresses []string      `json:"tcpAddresses"`
	ReadTimeout  time.Duration `json:"readTimeout"`
	WriteTimeout time.Duration `json:"writeTimeout"`
}

// UnmarshalJSON 支持字符串 (如 "5s") 与数字纳秒对 time.Duration 的反序列化
func (c *DNSConfig) UnmarshalJSON(data []byte) error {
	type Alias DNSConfig
	aux := &struct {
		ReadTimeout  any `json:"readTimeout"`
		WriteTimeout any `json:"writeTimeout"`
		*Alias
	}{
		Alias: (*Alias)(c),
	}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	if aux.ReadTimeout != nil {
		d, err := parseDurationValue(aux.ReadTimeout)
		if err != nil {
			return fmt.Errorf("解析 readTimeout 失败: %w", err)
		}
		c.ReadTimeout = d
	}
	if aux.WriteTimeout != nil {
		d, err := parseDurationValue(aux.WriteTimeout)
		if err != nil {
			return fmt.Errorf("解析 writeTimeout 失败: %w", err)
		}
		c.WriteTimeout = d
	}
	return nil
}

func parseDurationValue(v any) (time.Duration, error) {
	switch val := v.(type) {
	case string:
		return time.ParseDuration(val)
	case float64:
		return time.Duration(val), nil
	case int64:
		return time.Duration(val), nil
	default:
		return 0, fmt.Errorf("不支持的 duration 类型: %T", v)
	}
}

// IPCConfig 本地特权服务 IPC 接口配置
type IPCConfig struct {
	ListenAddress string `json:"listenAddress"` // 本地监听地址，如 "127.0.0.1:15353"
	AuthToken     string `json:"authToken"`     // 鉴权 Token
}

// TakeoverConfig 系统网卡 DNS 接管配置
type TakeoverConfig struct {
	AutoTakeoverOnStart bool   `json:"autoTakeoverOnStart"` // 启动时是否自动接管物理网卡
	StateFilePath       string `json:"stateFilePath"`       // 接管状态持久化文件路径
}

// Config 谛听 Windows 端完整核心配置
type Config struct {
	DNS      DNSConfig           `json:"dns"`
	Upstream core.ResolverConfig `json:"upstream"`
	IPC      IPCConfig           `json:"ipc"`
	Takeover TakeoverConfig      `json:"takeover"`
	Cache    core.CacheConfig    `json:"cache"`
}

// DefaultConfig 生成默认系统配置
func DefaultConfig() *Config {
	return &Config{
		DNS: DNSConfig{
			UDPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
			TCPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
			ReadTimeout:  5 * time.Second,
			WriteTimeout: 5 * time.Second,
		},
		Upstream: core.ResolverConfig{
			Mode: core.ModePrimaryBackup,
			Providers: []core.ProviderConfig{
				{ID: "primary-ali", Protocol: core.ProtocolPlain, Server: "223.5.5.5:53"},
				{ID: "backup-dnspod", Protocol: core.ProtocolPlain, Server: "119.29.29.29:53"},
			},
			Bootstrap: core.BootstrapConfig{
				Enabled: true,
				Servers: []core.BootstrapServer{
					{ID: "bs-ali", Name: "AliDNS", Address: "223.5.5.5:53", Weight: 1.0},
					{ID: "bs-dnspod", Name: "DNSPod", Address: "119.29.29.29:53", Weight: 1.0},
				},
			},
		},
		IPC: IPCConfig{
			ListenAddress: "127.0.0.1:15353",
			AuthToken:     "",
		},
		Takeover: TakeoverConfig{
			AutoTakeoverOnStart: false,
			StateFilePath:       "",
		},
		Cache: core.DefaultCacheConfig(),
	}
}
