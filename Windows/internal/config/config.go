package config

import (
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
	}
}
