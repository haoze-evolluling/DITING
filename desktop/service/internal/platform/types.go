package platform

import (
	"fmt"
	"time"
)

// AdapterInfo 表示单个网络适配器（Windows 适配器 / Linux 网络接口）的属性与 DNS 配置。
//
// 字段语义在各平台保持一致：
//   - ID 在 Windows 上为网卡 GUID，在 Linux 上为接口名（如 eth0）；
//   - IPv4DHCP / IPv6DHCP 表示该协议栈的 DNS 是否为自动获取（非静态配置）。
type AdapterInfo struct {
	ID                  string   `json:"id"`                  // 网卡标识（Windows: GUID；Linux: 接口名）
	Name                string   `json:"name"`                // 网卡别名，如 "WLAN"、"以太网"、"eth0"
	Description         string   `json:"description"`         // 网卡描述，如 "Intel(R) Wi-Fi 6E AX210 160MHz"
	Index               int      `json:"index"`               // 接口索引 InterfaceIndex / ifindex
	Status              string   `json:"status"`              // 连接状态，如 "Up"、"Disconnected"
	Gateway             string   `json:"gateway"`             // IPv4 默认网关，如 "192.168.1.1"
	IPv4DHCP            bool     `json:"ipv4DHCP"`            // IPv4 DNS 是否为自动获取
	IPv6DHCP            bool     `json:"ipv6DHCP"`            // IPv6 DNS 是否为自动获取
	IPv4DNS             []string `json:"ipv4DNS"`             // 原有 IPv4 DNS 服务器列表
	IPv6DNS             []string `json:"ipv6DNS"`             // 原有 IPv6 DNS 服务器列表
	IsPhysical          bool     `json:"isPhysical"`          // 是否为物理网卡（非虚拟）
	HasResidualLoopback bool     `json:"hasResidualLoopback"` // 是否存在残留的回环 DNS 配置 (127.*, ::1 等)
}

// AdapterState 记录接管前单个网卡的原始配置，用于安全还原。
type AdapterState struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Index       int      `json:"index"`
	Description string   `json:"description"`
	IPv4DHCP    bool     `json:"ipv4DHCP"`
	IPv6DHCP    bool     `json:"ipv6DHCP"`
	IPv4DNS     []string `json:"ipv4DNS"`
	IPv6DNS     []string `json:"ipv6DNS"`
}

// TakeoverState 整体 DNS 接管持久化状态，落盘后用于崩溃自愈。
type TakeoverState struct {
	Active    bool           `json:"active"`
	Version   string         `json:"version"`
	PID       int            `json:"pid"`
	Timestamp time.Time      `json:"timestamp"`
	Adapters  []AdapterState `json:"adapters"`
}

// LANAddressInfo 封装局域网 IP 信息及其来源适配器。
type LANAddressInfo struct {
	IP            string `json:"ip"`
	InterfaceName string `json:"interfaceName"`
	IsIPv6        bool   `json:"isIPv6"`
}

// PortConflict 记录占用 53 端口的冲突详情。
type PortConflict struct {
	Port         int    `json:"port"`
	Protocol     string `json:"protocol"`     // "UDP" 或 "TCP"
	LocalAddress string `json:"localAddress"` // 监听地址，如 "0.0.0.0:53"
	PID          int    `json:"pid"`          // 占用进程 PID
	ProcessName  string `json:"processName"`  // 占用进程名称
	ServiceName  string `json:"serviceName,omitempty"`
	IsICS        bool   `json:"isICS"`     // 是否为 Windows ICS (SharedAccess) 服务或 Linux 的 systemd-resolved stub
	IsSelf       bool   `json:"isSelf"`    // 是否为谛听服务自身占用的端口
	Diagnosis    string `json:"diagnosis"` // 针对性诊断与处置建议
}

// PortCheckResult 包含端口可用性探测汇总。
type PortCheckResult struct {
	Available  bool           `json:"available"`  // 目标监听套接字是否立即可用
	Conflicts  []PortConflict `json:"conflicts"`  // 系统中现存的端口冲突/监听列表
	HasICS     bool           `json:"hasICS"`     // 是否检测到可自动修复的系统级占用（Windows ICS / Linux resolved stub）
	CanAutofix bool           `json:"canAutofix"` // 是否支持一键自动修复
	Diagnostic string         `json:"diagnostic"` // 综合诊断报告建议
}

// PortConflictError 标识端口冲突专用错误类型，携带深度的系统冲突探测诊断信息。
type PortConflictError struct {
	Result *PortCheckResult
	Err    error
}

// Error 实现 error 接口。
func (e *PortConflictError) Error() string {
	if e.Result != nil && e.Result.Diagnostic != "" {
		return fmt.Sprintf("53 端口已被占用: %s", e.Result.Diagnostic)
	}
	if e.Err != nil {
		return fmt.Sprintf("53 端口已被占用: %v", e.Err)
	}
	return "53 端口已被占用，无法启动 DNS 监听器"
}

// Unwrap 支持 errors.Is / errors.As 链路穿透。
func (e *PortConflictError) Unwrap() error {
	return e.Err
}

// 开机自启托管机制标识。
const (
	// AutoStartMechanismService 系统服务自启：随系统启动，先于用户登录。
	AutoStartMechanismService = "service"
	// AutoStartMechanismLoginItem 用户登录自启：登录桌面后拉起。
	AutoStartMechanismLoginItem = "login_item"
	// AutoStartMechanismSystemd systemd 单元自启。
	AutoStartMechanismSystemd = "systemd"
	// AutoStartMechanismXDG XDG autostart 桌面条目自启。
	AutoStartMechanismXDG = "xdg"
	// AutoStartMechanismNone 未配置任何开机自启托管。
	AutoStartMechanismNone = "none"
)

// AutoStartStatus 宿主机开机自启托管状态。
//
// Web 控制台无法读取图形桌面的自启开关，只能以宿主机实际配置为准，
// 故同时给出生效机制与可读说明，避免把"由系统服务托管"误报为"未配置开机启动"。
type AutoStartStatus struct {
	Enabled   bool   `json:"enabled"`
	Mechanism string `json:"mechanism"` // service / login_item / systemd / xdg / none
	Detail    string `json:"detail"`
}

// CoreServiceStatus 后台核心服务状态。
type CoreServiceStatus struct {
	Installed      bool   `json:"installed"`
	Running        bool   `json:"running"`
	State          string `json:"state"` // running, stopped, not_installed, start_pending, stop_pending, unknown
	StateText      string `json:"stateText"`
	ExecutablePath string `json:"executablePath"`
	IsElevated     bool   `json:"isElevated"`
	CanInstall     bool   `json:"canInstall"`
	Message        string `json:"message"`
	// AutoStart 宿主机开机自启托管状态；旧版本服务可能不返回该字段。
	AutoStart *AutoStartStatus `json:"autoStart,omitempty"`
}
