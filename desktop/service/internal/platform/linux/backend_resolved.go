//go:build linux

package linux

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// resolvedBackend 通过 systemd-resolved (resolvectl) 管理逐网卡 DNS 配置。
//
// 接管方式：对每张网卡执行 resolvectl dns <iface> 127.0.0.1 ::1
// 并设定域名路由 ~. ，使全局查询均走本机监听器。
// 还原方式：优先按快照恢复原 DNS 列表；快照为空（原为自动获取）时
// 执行 resolvectl revert <iface> 交还给 DHCP/NetworkManager。
type resolvedBackend struct {
	executor platform.CommandExecutor
}

// Kind 返回后端类型。
func (b *resolvedBackend) Kind() dnsBackendKind { return backendSystemdResolved }

// Apply 将指定网卡的 DNS 指向本机回环解析器。
func (b *resolvedBackend) Apply(ctx context.Context, adapters []platform.AdapterInfo) error {
	if len(adapters) == 0 {
		return fmt.Errorf("无有效网卡可供接管")
	}

	var applied []string
	for _, a := range adapters {
		iface := interfaceNameFromAdapter(a)
		if iface == "" {
			continue
		}
		if _, err := runCommand(ctx, b.executor, "resolvectl", "dns", iface, "127.0.0.1", "::1"); err != nil {
			_ = b.rollbackApplied(ctx, applied)
			return fmt.Errorf("设置网卡 [%s] 解析地址失败: %w", iface, err)
		}
		// 已改 DNS 的网卡必须立即登记进回退集合：若下一步 domain 失败，
		// 它同样处于半成品状态，不能只回退前面「全完成」的网卡。
		applied = append(applied, iface)
		if _, err := runCommand(ctx, b.executor, "resolvectl", "domain", iface, "~."); err != nil {
			_ = b.rollbackApplied(ctx, applied)
			return fmt.Errorf("设置网卡 [%s] 域名路由失败: %w", iface, err)
		}
	}

	return nil
}

// rollbackApplied 在接管中途失败时回退已生效的网卡。
func (b *resolvedBackend) rollbackApplied(ctx context.Context, ifaces []string) error {
	var lastErr error
	for _, iface := range ifaces {
		if _, err := runCommand(ctx, b.executor, "resolvectl", "revert", iface); err != nil {
			lastErr = err
		}
	}
	return lastErr
}

// Restore 依据快照还原网卡 DNS 配置。
func (b *resolvedBackend) Restore(ctx context.Context, adapters []platform.AdapterState) error {
	var lastErr error
	for _, raw := range adapters {
		a := platform.CleanAdapterState(raw)
		iface := interfaceNameFromState(a)
		if iface == "" {
			continue
		}

		servers := mergeDualStackServers(a)
		if len(servers) == 0 {
			// 原配置为自动获取，交还系统托管
			if _, err := runCommand(ctx, b.executor, "resolvectl", "revert", iface); err != nil {
				lastErr = fmt.Errorf("还原网卡 [%s] 至自动获取失败: %w", iface, err)
			}
			continue
		}

		args := append([]string{"dns", iface}, servers...)
		if _, err := runCommand(ctx, b.executor, "resolvectl", args...); err != nil {
			lastErr = fmt.Errorf("还原网卡 [%s] 解析地址失败: %w", iface, err)
			continue
		}
		// 还原为默认域名路由（不再强制 ~. 走本机）
		_, _ = runCommand(ctx, b.executor, "resolvectl", "domain", iface, "~.")
	}
	return lastErr
}

// Flush 刷新 systemd-resolved 缓存。
func (b *resolvedBackend) Flush(ctx context.Context) error {
	_, err := runCommand(ctx, b.executor, "resolvectl", "flush-caches")
	return err
}

// mergeDualStackServers 合并快照中的 IPv4 与 IPv6 DNS 服务器，去重后返回。
func mergeDualStackServers(a platform.AdapterState) []string {
	seen := make(map[string]bool)
	var out []string
	for _, s := range append(append([]string{}, a.IPv4DNS...), a.IPv6DNS...) {
		s = strings.TrimSpace(s)
		if s == "" || seen[s] || isResidualLoopbackServer(s) {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}

// resolvedDropInSupported 报告是否可写入 resolved 的 drop-in 配置目录。
func resolvedDropInSupported() bool {
	if _, err := os.Stat(resolvedDropDir); err == nil {
		return true
	}
	// 目录不存在时尝试创建，具备 root 权限即可
	return os.MkdirAll(resolvedDropDir, 0o755) == nil
}
