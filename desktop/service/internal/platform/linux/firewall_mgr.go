//go:build linux

package linux

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// LinuxFirewallManager 实现 Linux 防火墙规则管理。
type LinuxFirewallManager struct {
	executor platform.CommandExecutor
}

// NewFirewallManager 构造 Linux 防火墙管理器。
func NewFirewallManager(executor platform.CommandExecutor) platform.FirewallManager {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	return &LinuxFirewallManager{executor: executor}
}

// CheckPort53 检测 53 端口防火墙放行规则是否生效。
func (m *LinuxFirewallManager) CheckPort53(ctx context.Context) (bool, error) {
	return CheckFirewallPort53(ctx, m.executor)
}

// ConfigurePort53 配置 53 端口防火墙放行规则。
func (m *LinuxFirewallManager) ConfigurePort53(ctx context.Context, enable bool) error {
	return ConfigureFirewallPort53(ctx, m.executor, enable)
}

// CheckWeb 检测 Web 管理端口防火墙放行规则是否生效。
func (m *LinuxFirewallManager) CheckWeb(ctx context.Context) (bool, error) {
	return CheckFirewallPortWeb(ctx, m.executor)
}

// ConfigureWeb 配置 Web 管理端口防火墙放行规则。
func (m *LinuxFirewallManager) ConfigureWeb(ctx context.Context, port int, enable bool) error {
	return ConfigureFirewallPortWeb(ctx, m.executor, port, enable)
}
