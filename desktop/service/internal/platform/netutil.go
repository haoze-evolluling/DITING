package platform

import (
	"net"
	"regexp"
	"sort"
	"strings"
)

// virtualPattern 匹配常见虚拟网卡、VPN、隧道、回环与过滤驱动的关键词。
//
// 前段为 Windows 适配器命名习惯，末段（veth / virbr / br- / docker0 / wgN）为
// Linux 网络接口命名习惯。两类关键词互不冲突，故统一在此判定，避免各平台重复实现。
var virtualPattern = regexp.MustCompile(`(?i)(Hyper-V|Virtual|VMware|VirtualBox|TAP|TUN|singbox|sing-tun|VPN|Tailscale|WireGuard|ZeroTier|Loopback|Npcap|Clat|WFP|WAN Miniport|Default Switch|Host-Only|vEthernet|WSL|Docker|Bluetooth|蓝牙|Radmin|Hamachi|veth|virbr|br-|docker0|wg[0-9])`)

// IsVirtualAdapter 判断网卡是否为虚拟网卡或回环适配器。
func IsVirtualAdapter(name, description string, virtualFlag bool) bool {
	if virtualFlag {
		return true
	}
	if virtualPattern.MatchString(name) || virtualPattern.MatchString(description) {
		return true
	}
	return false
}

// HasValidIPv4Gateway 校验 IPv4 默认网关是否合法（非空、非 0.0.0.0、非回环）。
func HasValidIPv4Gateway(gateway string) bool {
	gw := strings.TrimSpace(gateway)
	if gw == "" || gw == "0.0.0.0" {
		return false
	}
	ip := net.ParseIP(gw)
	if ip == nil || ip.To4() == nil {
		return false
	}
	return !ip.IsLoopback() && !ip.IsUnspecified()
}

// IsLoopbackOrLocalIP 判断 IP 字符串是否属于本地回环 (127.0.0.0/8, ::1) 或未指定/全零地址。
func IsLoopbackOrLocalIP(ipStr string) bool {
	trimmed := strings.TrimSpace(ipStr)
	if trimmed == "" {
		return false
	}
	if host, _, err := net.SplitHostPort(trimmed); err == nil {
		trimmed = host
	}
	trimmed = strings.Trim(trimmed, "[]")
	ip := net.ParseIP(trimmed)
	if ip != nil {
		return ip.IsLoopback() || ip.IsUnspecified()
	}
	lower := strings.ToLower(trimmed)
	return strings.HasPrefix(lower, "127.") || lower == "::1" || lower == "0.0.0.0" || lower == "::" || lower == "localhost"
}

// FilterLoopbackIPs 过滤切片中的本地回环地址与未指定地址。
func FilterLoopbackIPs(ips []string) []string {
	if len(ips) == 0 {
		return []string{}
	}
	clean := make([]string, 0, len(ips))
	for _, ip := range ips {
		if !IsLoopbackOrLocalIP(ip) {
			trimmed := strings.TrimSpace(ip)
			if trimmed != "" {
				clean = append(clean, trimmed)
			}
		}
	}
	return clean
}

// CleanAdapterState 净化网卡快照配置，过滤自身接管的回环地址（127.0.0.0/8、::1 等）。
//
// 若过滤后原始 DNS 为空，则自动将其修正为 DHCP 自动获取，避免恢复为静态 127.0.0.1 导致断网。
func CleanAdapterState(a AdapterState) AdapterState {
	cleaned := a
	cleaned.IPv4DNS = FilterLoopbackIPs(a.IPv4DNS)
	cleaned.IPv6DNS = FilterLoopbackIPs(a.IPv6DNS)
	if len(cleaned.IPv4DNS) == 0 {
		cleaned.IPv4DHCP = true
	}
	if len(cleaned.IPv6DNS) == 0 {
		cleaned.IPv6DHCP = true
	}
	return cleaned
}

// GetLANAddresses 获取本机所有物理及有效活动局域网 IP 地址列表。
//
// 优先返回 IPv4 私有局域网地址（如 192.168.x.x, 10.x.x.x），后续紧跟全局 IPv6。
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

				if IsPrivateIPv4(ip4) {
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

// IsPrivateIPv4 判断 IPv4 是否为 RFC 1918 私有地址空间。
func IsPrivateIPv4(ip net.IP) bool {
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

// IsPortBindConflict 判断底层错误是否包含套接字绑定冲突关键词。
//
// 同时覆盖 Windows（WSAEADDRINUSE / "only one usage"）与 Linux/macOS
// （"address already in use"）的报错文案。
func IsPortBindConflict(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "bind") ||
		strings.Contains(msg, "only one usage") ||
		strings.Contains(msg, "address already in use") ||
		strings.Contains(msg, "wsaeaddrinuse")
}
