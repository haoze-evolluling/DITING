//go:build linux

package linux

import (
	"bufio"
	"context"
	"net"
	"regexp"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// linkLinePattern 匹配 resolvectl dns 输出中的链路行，例如：
//
//	Link 2 (eth0): 192.168.1.1 2001:db8::1
//	Link 3 (wlan0):
var linkLinePattern = regexp.MustCompile(`^Link\s+\d+\s+\(([^)]+)\)\s*:?\s*(.*)$`)

// scanConfiguredDNSServers 探测各网卡当前生效的 DNS 服务器列表。
//
// 按 systemd-resolved → NetworkManager → /etc/resolv.conf 的顺序探测，
// 返回 接口名 → 服务器列表 的映射，用于网卡枚举时填充 DNS 快照。
func scanConfiguredDNSServers(ctx context.Context) map[string][]string {
	if commandExists("resolvectl") {
		if m := serversFromResolvectl(ctx); len(m) > 0 {
			return m
		}
	}
	if commandExists("nmcli") {
		if m := serversFromNmcli(ctx); len(m) > 0 {
			return m
		}
	}
	return serversFromResolvConf()
}

// serversFromResolvectl 解析 `resolvectl dns` 输出。
func serversFromResolvectl(ctx context.Context) map[string][]string {
	out, err := runCommand(ctx, nil, "resolvectl", "dns")
	if err != nil {
		return nil
	}
	return parseResolvectlDNS(out)
}

// parseResolvectlDNS 从 `resolvectl dns` 的输出文本中提取 接口名 → 服务器列表。
func parseResolvectlDNS(out string) map[string][]string {
	result := make(map[string][]string)
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		m := linkLinePattern.FindStringSubmatch(strings.TrimSpace(sc.Text()))
		if m == nil {
			continue
		}
		iface := strings.TrimSpace(m[1])
		servers := strings.Fields(m[2])
		if iface != "" && len(servers) > 0 {
			result[iface] = servers
		}
	}
	return result
}

// serversFromNmcli 解析 `nmcli` 活动连接的 IP4.DNS / IP6.DNS 字段。
func serversFromNmcli(ctx context.Context) map[string][]string {
	out, err := runCommand(ctx, nil, "nmcli", "-t", "-f", "DEVICE,IP4.DNS,IP6.DNS", "con", "show", "--active")
	if err != nil {
		return nil
	}

	result := make(map[string][]string)
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		fields := strings.Split(sc.Text(), ":")
		if len(fields) < 3 {
			continue
		}
		iface := strings.TrimSpace(fields[0])
		if iface == "" || iface == "lo" {
			continue
		}
		var servers []string
		for _, f := range fields[1:] {
			servers = append(servers, strings.Fields(f)...)
		}
		if len(servers) > 0 {
			result[iface] = servers
		}
	}
	return result
}

// serversFromResolvConf 在无托管服务时，将 /etc/resolv.conf 中的服务器
// 归属到所有处于 Up 状态的物理网卡（该文件本身不区分接口）。
func serversFromResolvConf() map[string][]string {
	servers := currentSystemServers()
	if len(servers) == 0 {
		return nil
	}

	ifaces, err := listManagedInterfaces()
	if err != nil {
		return nil
	}

	result := make(map[string][]string)
	for _, iface := range ifaces {
		if !ifaceUsableForResolvConf(iface) {
			continue
		}
		result[iface.Name] = servers
	}
	return result
}

// ifaceUsableForResolvConf 判断接口是否应归属 resolv.conf 中的服务器。
func ifaceUsableForResolvConf(iface net.Interface) bool {
	if iface.Flags&net.FlagLoopback != 0 {
		return false
	}
	if !ifaceIsUp(iface) {
		return false
	}
	return !platform.IsVirtualAdapter(iface.Name, "", ifaceHasPointToPoint(iface))
}
