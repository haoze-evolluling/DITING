package windows

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"regexp"
	"strings"
)

// virtualPattern 匹配常见虚拟网卡、VPN、隧道、回环与过滤驱动的关键词
var virtualPattern = regexp.MustCompile(`(?i)(Hyper-V|Virtual|VMware|VirtualBox|TAP|TUN|singbox|sing-tun|VPN|Tailscale|WireGuard|ZeroTier|Loopback|Npcap|Clat|WFP|WAN Miniport|Default Switch|Host-Only)`)

// AdapterInfo 表示 Windows 适配器属性与 DNS 配置
type AdapterInfo struct {
	ID          string   `json:"id"`          // 网卡 GUID，如 {2D46BA6A-1CED-4E84-9956-D2FD033CCEFA}
	Name        string   `json:"name"`        // 网卡别名，如 "WLAN"、"以太网"
	Description string   `json:"description"` // 网卡描述，如 "Intel(R) Wi-Fi 6E AX210 160MHz"
	Index       int      `json:"index"`       // 接口索引 InterfaceIndex
	Status      string   `json:"status"`      // 连接状态，如 "Up"、"Disconnected"
	Gateway     string   `json:"gateway"`     // IPv4 默认网关，如 "192.168.1.1"
	IPv4DHCP    bool     `json:"ipv4DHCP"`    // IPv4 是否为 DHCP 动态获取
	IPv6DHCP    bool     `json:"ipv6DHCP"`    // IPv6 是否为 DHCP 动态获取
	IPv4DNS     []string `json:"ipv4DNS"`     // 原有 IPv4 DNS 服务器列表
	IPv6DNS     []string `json:"ipv6DNS"`     // 原有 IPv6 DNS 服务器列表
	IsPhysical  bool     `json:"isPhysical"`  // 是否为物理网卡（非虚拟）
}

// AdapterScanner 定义网卡枚举与扫描接口
type AdapterScanner interface {
	ScanAll(ctx context.Context) ([]AdapterInfo, error)
	GetActivePhysicalAdapters(ctx context.Context) ([]AdapterInfo, error)
}

// PowerShellAdapterScanner 基于 PowerShell 的物理网卡扫描器
type PowerShellAdapterScanner struct {
	executor CommandExecutor
}

// NewAdapterScanner 创建网卡扫描器
func NewAdapterScanner(executor CommandExecutor) *PowerShellAdapterScanner {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	return &PowerShellAdapterScanner{executor: executor}
}

// adapterRawDTO 接收 PowerShell JSON 序列化的网卡结构
type adapterRawDTO struct {
	ID          string          `json:"ID"`
	Name        string          `json:"Name"`
	Description string          `json:"Description"`
	Index       int             `json:"Index"`
	Status      string          `json:"Status"`
	Gateway     string          `json:"Gateway"`
	IPv4DHCP    bool            `json:"IPv4DHCP"`
	IPv6DHCP    bool            `json:"IPv6DHCP"`
	IPv4DNS     json.RawMessage `json:"IPv4DNS"`
	IPv6DNS     json.RawMessage `json:"IPv6DNS"`
	Virtual     bool            `json:"Virtual"`
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

// parseStringOrSlice 解析 PowerShell 序列化时可能产生的单个字符串或字符串数组
func parseStringOrSlice(raw json.RawMessage) []string {
	if len(raw) == 0 || string(raw) == "null" {
		return []string{}
	}
	var arr []string
	if err := json.Unmarshal(raw, &arr); err == nil {
		clean := make([]string, 0, len(arr))
		for _, s := range arr {
			s = strings.TrimSpace(s)
			if s != "" {
				clean = append(clean, s)
			}
		}
		return clean
	}
	var single string
	if err := json.Unmarshal(raw, &single); err == nil {
		single = strings.TrimSpace(single)
		if single != "" {
			return []string{single}
		}
	}
	return []string{}
}

// extractJSON 从可能包含控制台输出、警告前缀或后缀的文本中提取合法的 JSON 数组或对象
func extractJSON(s string) string {
	trimmed := strings.TrimSpace(s)
	trimmed = strings.TrimPrefix(trimmed, "\xef\xbb\xbf") // 剥除可能附带的 UTF-8 BOM
	trimmed = strings.TrimSpace(trimmed)
	if trimmed == "" || trimmed == "null" {
		return trimmed
	}
	if json.Valid([]byte(trimmed)) {
		return trimmed
	}

	// 扫描寻找包含对象的合法 JSON 数组或独立 JSON 对象
	candidate := findValidJSON(trimmed)
	if candidate != "" {
		return candidate
	}
	return trimmed
}

func findValidJSON(s string) string {
	n := len(s)
	var best string
	for i := 0; i < n; i++ {
		start := s[i]
		if start != '[' && start != '{' {
			continue
		}
		var end byte = ']'
		if start == '{' {
			end = '}'
		}

		depth := 0
		inString := false
		escaped := false
		for j := i; j < n; j++ {
			c := s[j]
			if inString {
				if escaped {
					escaped = false
				} else if c == '\\' {
					escaped = true
				} else if c == '"' {
					inString = false
				}
				continue
			}
			if c == '"' {
				inString = true
			} else if c == start {
				depth++
			} else if c == end {
				depth--
				if depth == 0 {
					candidate := s[i : j+1]
					if strings.Contains(candidate, "{") && json.Valid([]byte(candidate)) {
						if len(candidate) > len(best) {
							best = candidate
						}
					}
					break
				}
			}
		}
	}
	return best
}

// adapterScanScript PowerShell 网卡信息提取脚本，设置静默错误处理防止特殊虚拟网卡抛出错误流
const adapterScanScript = `
$ErrorActionPreference = 'SilentlyContinue';
$ProgressPreference = 'SilentlyContinue';
Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
    $a = $_;
    $ip = try { Get-NetIPConfiguration -InterfaceIndex $a.InterfaceIndex -ErrorAction SilentlyContinue 2>$null } catch { $null };
    $gw = if ($ip -and $ip.IPv4DefaultGateway) { $ip.IPv4DefaultGateway.NextHop } else { '' };
    $v4dns = if ($ip -and $ip.DNSServer) { @(($ip.DNSServer | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses) } else { @() };
    $v6dns = if ($ip -and $ip.DNSServer) { @(($ip.DNSServer | Where-Object { $_.AddressFamily -eq 23 }).ServerAddresses) } else { @() };
    $reg = if ($a.InterfaceGuid) { try { Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $a.InterfaceGuid) -ErrorAction SilentlyContinue 2>$null } catch { $null } } else { $null };
    $v4dhcp = if ($reg) { ($reg.EnableDHCP -eq 1) -and ([string]::IsNullOrWhiteSpace($reg.NameServer)) } else { $true };
    $reg6 = if ($a.InterfaceGuid) { try { Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\' + $a.InterfaceGuid) -ErrorAction SilentlyContinue 2>$null } catch { $null } } else { $null };
    $v6dhcp = if ($reg6) { [string]::IsNullOrWhiteSpace($reg6.NameServer) } else { $true };
    [PSCustomObject]@{
        ID = $a.InterfaceGuid;
        Name = $a.Name;
        Description = $a.InterfaceDescription;
        Index = $a.InterfaceIndex;
        Status = [string]$a.Status;
        Gateway = [string]$gw;
        IPv4DHCP = [bool]$v4dhcp;
        IPv6DHCP = [bool]$v6dhcp;
        IPv4DNS = $v4dns;
        IPv6DNS = $v6dns;
        Virtual = [bool]$a.Virtual;
    }
} | ConvertTo-Json -Depth 3
`

// ScanAll 枚举系统中的所有网卡
func (s *PowerShellAdapterScanner) ScanAll(ctx context.Context) ([]AdapterInfo, error) {
	out, err := s.executor.RunPowerShell(ctx, adapterScanScript)
	if err != nil {
		return nil, fmt.Errorf("执行网卡扫描 PowerShell 脚本失败: %w (输出: %s)", err, out)
	}
	return parseAdapterJSON(out)
}

// GetActivePhysicalAdapters 筛选出当前处于 Up 状态且具备有效 IPv4 默认网关的活动物理网卡
func (s *PowerShellAdapterScanner) GetActivePhysicalAdapters(ctx context.Context) ([]AdapterInfo, error) {
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

// parseAdapterJSON 解析 PowerShell 输出的 JSON 数据
func parseAdapterJSON(output string) ([]AdapterInfo, error) {
	trimmed := extractJSON(output)
	if trimmed == "" || trimmed == "null" {
		return []AdapterInfo{}, nil
	}

	var rawList []adapterRawDTO
	if err := json.Unmarshal([]byte(trimmed), &rawList); err != nil {
		var single adapterRawDTO
		if errSingle := json.Unmarshal([]byte(trimmed), &single); errSingle != nil {
			return nil, fmt.Errorf("解析网卡 JSON 失败: %w (原文: %s)", err, strings.TrimSpace(output))
		}
		rawList = []adapterRawDTO{single}
	}

	results := make([]AdapterInfo, 0, len(rawList))
	for _, raw := range rawList {
		isVirt := IsVirtualAdapter(raw.Name, raw.Description, raw.Virtual)
		results = append(results, AdapterInfo{
			ID:          raw.ID,
			Name:        raw.Name,
			Description: raw.Description,
			Index:       raw.Index,
			Status:      raw.Status,
			Gateway:     raw.Gateway,
			IPv4DHCP:    raw.IPv4DHCP,
			IPv6DHCP:    raw.IPv6DHCP,
			IPv4DNS:     parseStringOrSlice(raw.IPv4DNS),
			IPv6DNS:     parseStringOrSlice(raw.IPv6DNS),
			IsPhysical:  !isVirt,
		})
	}
	return results, nil
}
