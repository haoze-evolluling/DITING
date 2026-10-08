package windows

import (
	"net"
	"sort"
)

// LANAddressInfo 封装局域网 IP 信息及其来源适配器
type LANAddressInfo struct {
	IP            string `json:"ip"`
	InterfaceName string `json:"interfaceName"`
	IsIPv6        bool   `json:"isIPv6"`
}

// GetLANAddresses 获取本机所有物理及有效活动局域网 IP 地址列表
// 优先返回 IPv4 私有局域网地址（如 192.168.x.x, 10.x.x.x），后续紧跟全局 IPv6
func GetLANAddresses() ([]string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	return extractLANAddresses(ifaces), nil
}

func extractLANAddresses(ifaces []net.Interface) []string {
	var v4Privates []string
	var v4Others []string
	var v6Addrs []string
	seen := make(map[string]bool)

	for _, iface := range ifaces {
		// 忽略处于关闭状态、本地回环、点对点通道或匹配常见虚拟适配器特征的接口
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagPointToPoint != 0 {
			continue
		}
		if IsVirtualAdapter(iface.Name, "", false) {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}

			if ip == nil || ip.IsLoopback() || ip.IsUnspecified() || ip.IsMulticast() {
				continue
			}

			if ip4 := ip.To4(); ip4 != nil {
				// 排除 169.254.x.x (APIPA Link-local) 及全广播
				if ip4.IsLinkLocalUnicast() || ip4.Equal(net.IPv4bcast) {
					continue
				}
				str := ip4.String()
				if seen[str] {
					continue
				}
				seen[str] = true

				if isPrivateIPv4(ip4) {
					v4Privates = append(v4Privates, str)
				} else {
					v4Others = append(v4Others, str)
				}
			} else {
				// IPv6: 排除 Link-local (fe80::/10)
				if ip.IsLinkLocalUnicast() {
					continue
				}
				str := ip.String()
				if seen[str] {
					continue
				}
				seen[str] = true
				v6Addrs = append(v6Addrs, str)
			}
		}
	}

	sort.Strings(v4Privates)
	sort.Strings(v4Others)
	sort.Strings(v6Addrs)

	result := make([]string, 0, len(v4Privates)+len(v4Others)+len(v6Addrs))
	result = append(result, v4Privates...)
	result = append(result, v4Others...)
	result = append(result, v6Addrs...)
	return result
}

// isPrivateIPv4 判断 IPv4 是否为 RFC 1918 私有地址空间
func isPrivateIPv4(ip net.IP) bool {
	ip4 := ip.To4()
	if ip4 == nil {
		return false
	}
	// 10.0.0.0/8
	if ip4[0] == 10 {
		return true
	}
	// 172.16.0.0/12
	if ip4[0] == 172 && ip4[1] >= 16 && ip4[1] <= 31 {
		return true
	}
	// 192.168.0.0/16
	if ip4[0] == 192 && ip4[1] == 168 {
		return true
	}
	return false
}
