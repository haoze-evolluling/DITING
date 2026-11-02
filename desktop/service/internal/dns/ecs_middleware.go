package dns

import (
	"sync"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// ECSManager 动态管理 ECS 策略配置
type ECSManager struct {
	mu  sync.RWMutex
	cfg core.ECSConfig
}

// NewECSManager 创建 ECS 配置管理器
func NewECSManager(cfg core.ECSConfig) *ECSManager {
	return &ECSManager{cfg: cfg}
}

// Configure 更新 ECS 配置
func (m *ECSManager) Configure(cfg core.ECSConfig) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cfg = cfg
}

// GetConfig 获取当前配置快照
func (m *ECSManager) GetConfig() core.ECSConfig {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.cfg
}

// NewECSMiddleware 创建 RFC 7871 EDNS0 Client Subnet 处理中间件
// 深度借鉴自 Blocky (ecs_resolver.go) 与 dnscrypt-proxy (plugin_ecs.go)
func NewECSMiddleware(mgr *ECSManager) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if mgr == nil || ctx.Req == nil {
			return next()
		}

		cfg := mgr.GetConfig()
		if !cfg.Enabled {
			return next()
		}

		if cfg.CustomSubnet != "" {
			// 自定义子网透传/伪装模式：先剥离客户端可能自带的真实子网，再注入自定义伪装子网
			StripECS(ctx.Req)
			_ = SetECS(ctx.Req, cfg.CustomSubnet)
			ctx.Set("ecs_injected", cfg.CustomSubnet)
		} else if cfg.StripECS {
			// 隐私保护模式：剥离请求中携带的客户端真实子网以防信息泄露
			StripECS(ctx.Req)
			ctx.Set("ecs_stripped", true)
		}

		return next()
	}
}
