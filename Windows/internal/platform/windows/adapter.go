package windows

import (
	"context"
	"net"
	"regexp"
	"strings"
)

// virtualPattern 匹配常见虚拟网卡、VPN、隧道、回环与过滤驱动的关键词
var virtualPattern = regexp.MustCompile(`(?i)(Hyper-V|Virtual|VMware|VirtualBox|TAP|TUN|singbox|sing-tun|VPN|Tailscale|WireGuard|ZeroTier|Loopback|Npcap|Clat|WFP|WAN Miniport|Default Switch|Host-Only|vEthernet|WSL|Docker|Bluetooth|蓝牙|Radmin|Hamachi)`)

// AdapterInfo 表示 Windows 适配器属性与 DNS 配置
type AdapterInfo struct {
	ID                  string   `json:"id"`                  // 网卡 GUID，如 {2D46BA6A-1CED-4E84-9956-D2FD033CCEFA}
	Name                string   `json:"name"`                // 网卡别名，如 "WLAN"、"以太网"
	Description         string   `json:"description"`         // 网卡描述，如 "Intel(R) Wi-Fi 6E AX210 160MHz"
	Index               int      `json:"index"`               // 接口索引 InterfaceIndex
	Status              string   `json:"status"`              // 连接状态，如 "Up"、"Disconnected"
	Gateway             string   `json:"gateway"`             // IPv4 默认网关，如 "192.168.1.1"
	IPv4DHCP            bool     `json:"ipv4DHCP"`            // IPv4 是否为 DHCP 动态获取
	IPv6DHCP            bool     `json:"ipv6DHCP"`            // IPv6 是否为 DHCP 动态获取
	IPv4DNS             []string `json:"ipv4DNS"`             // 原有 IPv4 DNS 服务器列表
	IPv6DNS             []string `json:"ipv6DNS"`             // 原有 IPv6 DNS 服务器列表
	IsPhysical          bool     `json:"isPhysical"`          // 是否为物理网卡（非虚拟）
	HasResidualLoopback bool     `json:"hasResidualLoopback"` // 是否存在残留的回环 DNS 配置 (127.*, ::1 等)
}

// AdapterScanner 定义网卡枚举与扫描接口
type AdapterScanner interface {
	ScanAll(ctx context.Context) ([]AdapterInfo, error)
	GetActivePhysicalAdapters(ctx context.Context) ([]AdapterInfo, error)
}

// NativeAdapterScanner 基于 Windows 原生 API 的物理网卡扫描器
type NativeAdapterScanner struct{}

// NewAdapterScanner 创建网卡扫描器
func NewAdapterScanner(executor CommandExecutor) *NativeAdapterScanner {
	return &NativeAdapterScanner{}
}

// ScanAll 枚举系统中的所有网卡（调用 Windows 原生 API）
func (s *NativeAdapterScanner) ScanAll(ctx context.Context) ([]AdapterInfo, error) {
	return scanAdaptersNative(ctx)
}

// GetActivePhysicalAdapters 筛选出当前处于 Up 状态且具备有效 IPv4 默认网关的活动物理网卡
func (s *NativeAdapterScanner) GetActivePhysicalAdapters(ctx context.Context) ([]AdapterInfo, error) {
	all, err := s.ScanAll(ctx)
	if err != nil {
		return nil, err
	}

	filtered := make([]AdapterInfo, 0, len(all))
	for _, a := range all {
		if !a.IsPhysical {
			continue
		}
		if !strings.EqualFold(a.Status, "Up") {
			continue
		}
		if !HasValidIPv4Gateway(a.Gateway) {
			continue
		}
		filtered = append(filtered, a)
	}
	return filtered, nil
}

// IsVirtualAdapter 判断网卡是否为虚拟网卡或回环适配器
func IsVirtualAdapter(name, description string, virtualFlag bool) bool {
	if virtualFlag {
		return true
	}
	if virtualPattern.MatchString(name) || virtualPattern.MatchString(description) {
		return true
	}
	return false
}

// HasValidIPv4Gateway 校验 IPv4 默认网关是否合法（非空、非 0.0.0.0、非回环）
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

// IsLoopbackOrLocalIP 判断 IP 字符串是否属于本地回环 (127.0.0.0/8, ::1) 或未指定/全零地址
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

// FilterLoopbackIPs 过滤切片中的本地回环地址与未指定地址
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
