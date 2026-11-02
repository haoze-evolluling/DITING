//go:build linux

package linux

import (
	"bufio"
	"context"
	"fmt"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// networkManagerBackend 通过 NetworkManager (nmcli) 管理连接级 DNS 配置。
//
// 接管方式：对每个活动连接执行 nmcli con mod <conn> ipv4.dns 127.0.0.1
// 与 ipv6.dns ::1，并设置 ipv4.ignore-auto-dns yes 防止 DHCP 下发的 DNS 抢先，
// 随后 nmcli con up <conn> 使配置生效。
// 还原方式：按快照恢复原 DNS 列表与 ignore-auto-dns 原值，并重新激活连接。
type networkManagerBackend struct {
	executor platform.CommandExecutor
}

// Kind 返回后端类型。
func (b *networkManagerBackend) Kind() dnsBackendKind { return backendNetworkManager }

// Apply 将活动连接的 DNS 指向本机回环解析器。
func (b *networkManagerBackend) Apply(ctx context.Context, adapters []platform.AdapterInfo) error {
	conns, err := b.activeConnections(ctx)
	if err != nil {
		return err
	}
	if len(conns) == 0 {
		return fmt.Errorf("未找到由 NetworkManager 管理的活动连接")
	}

	var applied []string
	for _, conn := range conns {
		if err := b.modifyConnection(ctx, conn, []string{"127.0.0.1"}, []string{"::1"}, true); err != nil {
			_ = b.revertConnections(ctx, applied)
			return err
		}
		applied = append(applied, conn)
	}
	return nil
}

// Restore 依据快照还原连接 DNS 配置。
func (b *networkManagerBackend) Restore(ctx context.Context, adapters []platform.AdapterState) error {
	conns, err := b.activeConnections(ctx)
	if err != nil {
		return err
	}

	var lastErr error
	for _, conn := range conns {
		var v4, v6 []string
		for _, raw := range adapters {
			a := platform.CleanAdapterState(raw)
			if !connectionMatchesAdapter(conn, a) {
				continue
			}
			v4 = a.IPv4DNS
			v6 = a.IPv6DNS
			break
		}
		if err := b.modifyConnection(ctx, conn, v4, v6, false); err != nil {
			lastErr = err
		}
	}
	return lastErr
}

// Flush 在 NetworkManager 环境中回退为 resolvectl（若存在），否则无操作。
func (b *networkManagerBackend) Flush(ctx context.Context) error {
	if commandExists("resolvectl") {
		_, err := runCommand(ctx, b.executor, "resolvectl", "flush-caches")
		return err
	}
	return nil
}

// activeConnections 列出当前处于已激活状态的 NetworkManager 连接名。
func (b *networkManagerBackend) activeConnections(ctx context.Context) ([]string, error) {
	out, err := runCommand(ctx, b.executor, "nmcli", "-t", "-f", "NAME,DEVICE,STATE", "con", "show", "--active")
	if err != nil {
		return nil, fmt.Errorf("查询 NetworkManager 活动连接失败: %w", err)
	}

	var conns []string
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		fields := strings.Split(sc.Text(), ":")
		if len(fields) < 3 {
			continue
		}
		name := strings.TrimSpace(fields[0])
		if name == "" || name == "lo" {
			continue
		}
		conns = append(conns, name)
	}
	return conns, nil
}

// modifyConnection 修改指定连接的 DNS 设置并重新激活。
//
// v4/v6 为空切片时表示清除静态 DNS（恢复自动获取）。
func (b *networkManagerBackend) modifyConnection(ctx context.Context, conn string, v4, v6 []string, ignoreAuto bool) error {
	v4Arg := strings.Join(v4, ",")
	v6Arg := strings.Join(v6, ",")
	ignoreArg := "no"
	if ignoreAuto {
		ignoreArg = "yes"
	}

	args := []string{
		"con", "mod", conn,
		"ipv4.dns", v4Arg,
		"ipv6.dns", v6Arg,
		"ipv4.ignore-auto-dns", ignoreArg,
		"ipv6.ignore-auto-dns", ignoreArg,
	}
	if _, err := runCommand(ctx, b.executor, "nmcli", args...); err != nil {
		return fmt.Errorf("修改连接 [%s] 的 DNS 设置失败: %w", conn, err)
	}

	if _, err := runCommand(ctx, b.executor, "nmcli", "con", "up", conn); err != nil {
		return fmt.Errorf("重新激活连接 [%s] 失败: %w", conn, err)
	}
	return nil
}

// revertConnections 在接管中途失败时回退已生效的连接。
func (b *networkManagerBackend) revertConnections(ctx context.Context, conns []string) error {
	var lastErr error
	for _, c := range conns {
		if err := b.modifyConnection(ctx, c, nil, nil, false); err != nil {
			lastErr = err
		}
	}
	return lastErr
}

// connectionMatchesAdapter 判断 NetworkManager 连接是否对应给定网卡快照。
func connectionMatchesAdapter(conn string, a platform.AdapterState) bool {
	name := interfaceNameFromState(a)
	return conn == name || strings.EqualFold(conn, a.Name)
}
