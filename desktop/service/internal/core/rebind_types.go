package core

// RebindConfig DNS Rebinding 攻击防御配置
// 借鉴自 blocky (rebinding_resolver.go) 与 AdGuard Home (access.go)
type RebindConfig struct {
	Enabled        bool     `json:"enabled"`
	AllowedDomains []string `json:"allowedDomains"` // 白名单域名或后缀 (例如 "router.lan", ".lan", ".local")
}

// DefaultRebindConfig 默认 Rebind 防御配置
func DefaultRebindConfig() RebindConfig {
	return RebindConfig{
		Enabled: true,
		AllowedDomains: []string{
			"localhost",
			".local",
			".lan",
			".home.arpa",
			"in-addr.arpa",
			"ip6.arpa",
		},
	}
}
