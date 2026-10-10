package windows

import (
	"context"
	"fmt"
	"net"
	"os"
	"strings"
)

// PortConflict 记录占用 53 端口的冲突详情
type PortConflict struct {
	Port         int    `json:"port"`
	Protocol     string `json:"protocol"`     // "UDP" 或 "TCP"
	LocalAddress string `json:"localAddress"` // 监听地址，如 "0.0.0.0:53"
	PID          int    `json:"pid"`          // 占用进程 PID
	ProcessName  string `json:"processName"`  // 占用进程名称
	ServiceName  string `json:"serviceName,omitempty"`
	IsICS        bool   `json:"isICS"`     // 是否为 Windows ICS (SharedAccess) 网络共享服务
	IsSelf       bool   `json:"isSelf"`    // 是否为谛听服务自身占用的端口
	Diagnosis    string `json:"diagnosis"` // 针对性诊断与处置建议
}

// PortCheckResult 包含 53 端口可用性探测汇总
type PortCheckResult struct {
	Available  bool           `json:"available"`  // 目标监听套接字是否立即可用
	Conflicts  []PortConflict `json:"conflicts"`  // 系统中现存的 53 端口冲突/监听列表
	HasICS     bool           `json:"hasICS"`     // 是否检测到 ICS 服务运行
	CanAutofix bool           `json:"canAutofix"` // 是否支持一键自动修复（如由 ICS 服务导致冲突）
	Diagnostic string         `json:"diagnostic"` // 综合诊断报告建议
}

// PortChecker 定义端口冲突探测接口
type PortChecker interface {
	CheckPort53(ctx context.Context) (*PortCheckResult, error)
	CheckPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*PortCheckResult, error)
	AutofixPort53(ctx context.Context) (*PortCheckResult, error)
}

// WindowsPortChecker Windows 平台 53 端口占用与冲突检测器
type WindowsPortChecker struct {
	executor CommandExecutor
}

// NewPortChecker 创建端口检测器
func NewPortChecker(executor CommandExecutor) *WindowsPortChecker {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	return &WindowsPortChecker{executor: executor}
}

// PortConflictError 标识 53 端口冲突专用错误类型，包含深度的系统冲突探测诊断信息
type PortConflictError struct {
	Result *PortCheckResult
	Err    error
}

func (e *PortConflictError) Error() string {
	if e.Result != nil && e.Result.Diagnostic != "" {
		return fmt.Sprintf("53 端口已被占用: %s", e.Result.Diagnostic)
	}
	if e.Err != nil {
		return fmt.Sprintf("53 端口已被占用: %v", e.Err)
	}
	return "53 端口已被占用，无法启动 DNS 监听器"
}

func (e *PortConflictError) Unwrap() error {
	return e.Err
}

// IsPort53Available 快速测试 127.0.0.1:53 是否可绑定 (UDP 与 TCP)
func IsPort53Available() bool {
	return TestUDPBind("127.0.0.1:53") && TestTCPBind("127.0.0.1:53")
}

// AreAddressesAvailable 快速测试指定地址列表是否均可成功绑定
func AreAddressesAvailable(udpAddrs, tcpAddrs []string) bool {
	for _, u := range udpAddrs {
		if !TestUDPBind(u) {
			return false
		}
	}
	for _, t := range tcpAddrs {
		if !TestTCPBind(t) {
			return false
		}
	}
	return true
}

// IsPortBindConflict 判断底层错误是否包含套接字绑定冲突关键词
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

// CheckPort53 探测默认回环地址 (127.0.0.1:53) 的端口冲突状况
func (c *WindowsPortChecker) CheckPort53(ctx context.Context) (*PortCheckResult, error) {
	return c.CheckPort53ForAddresses(ctx, []string{"127.0.0.1:53"}, []string{"127.0.0.1:53"})
}

// CheckPort53ForAddresses 针对实际配置的目标双栈 UDP 与 TCP 监听地址执行精准探测
// 遵循 AdGuard Home 的 Real Socket Check 原则：以实际目标套接字探测结果为准。
func (c *WindowsPortChecker) CheckPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*PortCheckResult, error) {
	if len(udpAddrs) == 0 && len(tcpAddrs) == 0 {
		udpAddrs = []string{"127.0.0.1:53"}
		tcpAddrs = []string{"127.0.0.1:53"}
	}

	// 1. 本地尝试对所有目标地址进行轻量级绑定探测（Real Socket Check）
	udpFree := true
	for _, addr := range udpAddrs {
		if !TestUDPBind(addr) {
			udpFree = false
			break
		}
	}

	tcpFree := true
	for _, addr := range tcpAddrs {
		if !TestTCPBind(addr) {
			tcpFree = false
			break
		}
	}
	socketsFree := udpFree && tcpFree

	// 2. 通过 Windows 原生 API 深度检测全系统 53 端口监听实体及 ICS 状态
	conflicts, hasICS, diag, err := checkPort53Native(socketsFree, os.Getpid())
	if err != nil {
		return &PortCheckResult{
			Available:  socketsFree,
			Conflicts:  nil,
			HasICS:     false,
			CanAutofix: false,
			Diagnostic: fmt.Sprintf("53 端口套接字绑定探测: UDP=%v, TCP=%v (原生诊断失败: %v)", udpFree, tcpFree, err),
		}, nil
	}

	hasOtherConflict := false
	hasSelfListener := false
	for _, conf := range conflicts {
		if conf.IsSelf {
			hasSelfListener = true
		} else {
			hasOtherConflict = true
		}
	}

	// 3. 依据 Real Socket Check 判定目标地址真实可用性与 Autofix 资格：
	// - 若目标套接字绑定成功（socketsFree），或当前已被自身 PID 监听，则 available = true；
	// - 若当前仅监听回环 (127.0.0.1)，且套接字真实测试绑定成功，不因后台存在 ICS 服务而一票否决；
	// - 若套接字绑定失败（!socketsFree），且检测到 ICS 正在运行，判定为不可用且 canAutofix = true；
	// - 若套接字绑定失败且非 ICS 造成，判定为不可用且 canAutofix = false。
	available := false
	canAutofix := false

	if socketsFree || hasSelfListener {
		available = true
		canAutofix = false
		if hasICS && !isOnlyLoopback(udpAddrs, tcpAddrs) {
			// 若启用了非回环地址但由于某种原因暂时通过（极少情况），保留 ICS 提示
		}
	} else {
		available = false
		if hasICS {
			canAutofix = true
			if !isOnlyLoopback(udpAddrs, tcpAddrs) {
				diag = fmt.Sprintf("当前启用了局域网共享监听 (0.0.0.0:53)，检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行并占用了 0.0.0.0:53。\n排查建议：点击【一键自动修复并启动】自动停止并禁用 ICS 服务，或关闭局域网共享模式降级为仅本机回环监听。\n%s", diag)
			} else {
				diag = fmt.Sprintf("53 端口套接字绑定失败。检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行。\n排查建议：点击【一键自动修复并启动】自动停止并禁用 ICS 服务后重试。\n%s", diag)
			}
		} else if hasOtherConflict {
			canAutofix = false
		}
	}

	return &PortCheckResult{
		Available:  available,
		Conflicts:  conflicts,
		HasICS:     hasICS,
		CanAutofix: canAutofix,
		Diagnostic: diag,
	}, nil
}

func isOnlyLoopback(udpAddrs, tcpAddrs []string) bool {
	for _, a := range append(udpAddrs, tcpAddrs...) {
		h, _, err := net.SplitHostPort(a)
		if err != nil {
			h = a
		}
		if h != "127.0.0.1" && h != "::1" && h != "localhost" {
			return false
		}
	}
	return true
}

// TestUDPBind 测试指定 UDP 地址是否能够成功绑定
func TestUDPBind(addr string) bool {
	netType := "udp4"
	if isIPv6Addr(addr) {
		netType = "udp6"
	}
	conn, err := net.ListenPacket(netType, addr)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

// TestTCPBind 测试指定 TCP 地址是否能够成功绑定
func TestTCPBind(addr string) bool {
	netType := "tcp4"
	if isIPv6Addr(addr) {
		netType = "tcp6"
	}
	l, err := net.Listen(netType, addr)
	if err != nil {
		return false
	}
	_ = l.Close()
	return true
}

func isIPv6Addr(addr string) bool {
	h, _, err := net.SplitHostPort(addr)
	if err != nil {
		h = addr
	}
	return strings.Contains(h, ":") || strings.HasPrefix(addr, "[::]")
}

func ternary[T any](cond bool, a, b T) T {
	if cond {
		return a
	}
	return b
}
