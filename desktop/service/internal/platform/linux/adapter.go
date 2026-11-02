//go:build linux

package linux

import (
	"context"
	"net"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// NativeAdapterScanner 基于 Linux 标准接口（net.Interfaces + /proc + /sys）的网卡扫描器。
//
// AdapterInfo / AdapterScanner 等跨平台类型与接口定义于 internal/platform，
// 本类型仅负责 Linux 侧枚举实现，接口名（eth0、wlan0）即 ID。
type NativeAdapterScanner struct{}

// NewAdapterScanner 创建网卡扫描器。
func NewAdapterScanner(executor platform.CommandExecutor) *NativeAdapterScanner {
	return &NativeAdapterScanner{}
}

// ScanAll 枚举系统中所有网络接口（排除回环）。
func (s *NativeAdapterScanner) ScanAll(ctx context.Context) ([]platform.AdapterInfo, error) {
	ifaces, err := listManagedInterfaces()
	if err != nil {
		return nil, err
	}

	servers := scanConfiguredDNSServers(ctx)

	results := make([]platform.AdapterInfo, 0, len(ifaces))
	for _, iface := range ifaces {
		// 跳过回环接口
		if iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		desc := ifaceDescription(iface.Name)
		isVirt := platform.IsVirtualAdapter(iface.Name, desc, ifaceHasPointToPoint(iface))
		gateway := readDefaultGateway(iface.Name)

		v4DNS, v6DNS := splitServers(servers[iface.Name])
		status := "Disconnected"
		if ifaceIsUp(iface) {
			status = "Up"
		}

		results = append(results, platform.AdapterInfo{
			ID:                  iface.Name,
			Name:                iface.Name,
			Description:         desc,
			Index:               iface.Index,
			Status:              status,
			Gateway:             gateway,
			IPv4DHCP:            len(v4DNS) == 0,
			IPv6DHCP:            len(v6DNS) == 0,
			IPv4DNS:             v4DNS,
			IPv6DNS:             v6DNS,
			IsPhysical:          !isVirt,
			HasResidualLoopback: hasLoopbackServer(servers[iface.Name]),
		})
	}
	return results, nil
}

// GetActivePhysicalAdapters 筛选出 Up 且具备有效 IPv4 网关的活动物理网卡。
func (s *NativeAdapterScanner) GetActivePhysicalAdapters(ctx context.Context) ([]platform.AdapterInfo, error) {
	all, err := s.ScanAll(ctx)
	if err != nil {
		return nil, err
	}

	filtered := make([]platform.AdapterInfo, 0, len(all))
	for _, a := range all {
		if !a.IsPhysical {
			continue
		}
		if !strings.EqualFold(a.Status, "Up") {
			continue
		}
		if !platform.HasValidIPv4Gateway(a.Gateway) {
			continue
		}
		filtered = append(filtered, a)
	}
	return filtered, nil
}

// splitServers 将 DNS 服务器列表按 IPv4 / IPv6 分类。
func splitServers(servers []string) (v4, v6 []string) {
	for _, s := range servers {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		if strings.Contains(s, ":") {
			v6 = append(v6, s)
		} else {
			v4 = append(v4, s)
		}
	}
	return v4, v6
}

// hasLoopbackServer 判断服务器列表中是否存在回环/本机地址。
func hasLoopbackServer(servers []string) bool {
	for _, s := range servers {
		if platform.IsLoopbackOrLocalIP(s) {
			return true
		}
	}
	return false
}
