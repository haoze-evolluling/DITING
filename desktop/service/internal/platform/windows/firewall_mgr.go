//go:build windows

package windows

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// WindowsFirewallManager 实现 Windows 防火墙规则管理。
type WindowsFirewallManager struct {
	executor platform.CommandExecutor
}

// NewFirewallManager 构造 Windows 防火墙管理器。
func NewFirewallManager(executor platform.CommandExecutor) platform.FirewallManager {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	return &WindowsFirewallManager{executor: executor}
}

// CheckPort53 检测 53 端口防火墙放行规则是否生效。
func (m *WindowsFirewallManager) CheckPort53(ctx context.Context) (bool, error) {
	return CheckFirewallPort53(ctx, m.executor)
}

// ConfigurePort53 配置 53 端口防火墙放行规则。
func (m *WindowsFirewallManager) ConfigurePort53(ctx context.Context, enable bool) error {
	return ConfigureFirewallPort53(ctx, m.executor, enable)
}

// CheckWeb 检测 Web 管理端口防火墙放行规则是否生效。
func (m *WindowsFirewallManager) CheckWeb(ctx context.Context) (bool, error) {
	return CheckFirewallPortWeb(ctx, m.executor)
}

// ConfigureWeb 配置 Web 管理端口防火墙放行规则。
func (m *WindowsFirewallManager) ConfigureWeb(ctx context.Context, port int, enable bool) error {
	return ConfigureFirewallPortWeb(ctx, m.executor, port, enable)
}
