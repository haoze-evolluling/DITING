package config

import (
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

// DNSConfig 本地 DNS 监听服务配置
type DNSConfig struct {
	UDPAddresses []string      `json:"udpAddresses"`
	TCPAddresses []string      `json:"tcpAddresses"`
	ReadTimeout  time.Duration `json:"readTimeout"`
	WriteTimeout time.Duration `json:"writeTimeout"`
	AllowLAN     bool          `json:"allowLAN"` // 是否启用局域网 DNS 服务器功能（监听 0.0.0.0 与所有局域网地址）
}

// EffectiveListenAddresses 根据 AllowLAN 配置返回实际应监听的双栈 UDP 与 TCP 地址
func (c *DNSConfig) EffectiveListenAddresses() (udpAddrs []string, tcpAddrs []string) {
	port := 53
	extractPort := func(addrs []string) int {
		for _, addr := range addrs {
			if _, pStr, err := net.SplitHostPort(addr); err == nil {
				if p, err := strconv.Atoi(pStr); err == nil && p > 0 {
					return p
				}
			}
		}
		return 53
	}
	if p := extractPort(c.UDPAddresses); p > 0 {
		port = p
	} else if p := extractPort(c.TCPAddresses); p > 0 {
		port = p
	}

	if c.AllowLAN {
		lanAddrs := []string{fmt.Sprintf("0.0.0.0:%d", port), fmt.Sprintf("[::]:%d", port)}
		return lanAddrs, lanAddrs
	}

	toLocal := func(addrs []string) []string {
		var res []string
		for _, addr := range addrs {
			host, pStr, err := net.SplitHostPort(addr)
			if err != nil {
				continue
			}
			if host == "0.0.0.0" || host == "" {
				res = append(res, fmt.Sprintf("127.0.0.1:%s", pStr))
			} else if host == "::" || host == "[::]" {
				res = append(res, fmt.Sprintf("[::1]:%s", pStr))
			} else {
				res = append(res, addr)
			}
		}
		if len(res) == 0 {
			res = []string{fmt.Sprintf("127.0.0.1:%d", port), fmt.Sprintf("[::1]:%d", port)}
		}
		return res
	}

	return toLocal(c.UDPAddresses), toLocal(c.TCPAddresses)
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

// WebConfig 局域网 Web 管理控制台配置
type WebConfig struct {
	Enabled        bool          `json:"enabled"`        // 是否启用局域网 Web 远程管理
	ListenPort     int           `json:"listenPort"`     // 独立端口（若为 0 则复用 IPC 端口）
	Username       string        `json:"username"`       // 管理员账号（默认 admin）
	PasswordHash   string        `json:"passwordHash"`   // 加盐密码哈希
	Salt           string        `json:"salt"`           // 盐值
	SessionTimeout time.Duration `json:"sessionTimeout"` // 会话有效时长（默认 7 * 24h）
}

// UnmarshalJSON 支持字符串 (如 "168h") 与数字纳秒对 time.Duration 的反序列化
func (c *WebConfig) UnmarshalJSON(data []byte) error {
	type Alias WebConfig
	aux := &struct {
		SessionTimeout any `json:"sessionTimeout"`
		*Alias
	}{
		Alias: (*Alias)(c),
	}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	if aux.SessionTimeout != nil {
		d, err := parseDurationValue(aux.SessionTimeout)
		if err != nil {
			return fmt.Errorf("解析 sessionTimeout 失败: %w", err)
		}
		c.SessionTimeout = d
	}
	return nil
}

// Config 谛听 Windows 端完整核心配置
type Config struct {
	DNS      DNSConfig           `json:"dns"`
	Upstream core.ResolverConfig `json:"upstream"`
	IPC      IPCConfig           `json:"ipc"`
	Takeover TakeoverConfig      `json:"takeover"`
	Cache    core.CacheConfig    `json:"cache"`
	Filter   core.FilterConfig   `json:"filter"`
	Web      WebConfig           `json:"web"`
}

// DefaultConfig 生成默认系统配置
func DefaultConfig() *Config {
	return &Config{
		DNS: DNSConfig{
			UDPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
			TCPAddresses: []string{"127.0.0.1:53", "[::1]:53"},
			ReadTimeout:  5 * time.Second,
			WriteTimeout: 5 * time.Second,
			AllowLAN:     false,
		},
		Upstream: core.ResolverConfig{
			Mode: core.ModePrimaryBackup,
			Providers: []core.ProviderConfig{
				{ID: "阿里云 (DoT)", Protocol: core.ProtocolDoT, Server: "dns.alidns.com:853"},
				{ID: "腾讯云 (DoT)", Protocol: core.ProtocolDoT, Server: "dot.pub:853"},
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
		Cache:  core.DefaultCacheConfig(),
		Filter: core.DefaultFilterConfig(),
		Web: WebConfig{
			Enabled:        true,
			ListenPort:     15353,
			Username:       "admin",
			PasswordHash:   "",
			Salt:           "",
			SessionTimeout: 7 * 24 * time.Hour,
		},
	}
}
