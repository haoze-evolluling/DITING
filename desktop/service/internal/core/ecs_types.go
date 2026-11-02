package core

// ECSConfig EDNS0 Client Subnet (RFC 7871) 隐私与分发策略配置
// 深度借鉴自 Blocky (ecs_resolver.go) 与 dnscrypt-proxy (plugin_ecs.go)
type ECSConfig struct {
	Enabled      bool   `json:"enabled"`      // 是否启用 ECS 策略处理
	StripECS     bool   `json:"stripECS"`     // 是否剥离客户端请求中的 ECS 选项以保护真实子网隐私（默认 true）
	CustomSubnet string `json:"customSubnet"` // 可选自定义转发的子网 CIDR（如 "203.0.113.0/24"），为空时不追加伪装子网
}

// DefaultECSConfig 默认 ECS 隐私保护配置
func DefaultECSConfig() ECSConfig {
	return ECSConfig{
		Enabled:      true,
		StripECS:     true,
		CustomSubnet: "",
	}
}
