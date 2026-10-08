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
	Available  bool           `json:"available"`  // 127.0.0.1:53 是否立即可用
	Conflicts  []PortConflict `json:"conflicts"`  // 系统中现存的 53 端口冲突/监听列表
	HasICS     bool           `json:"hasICS"`     // 是否检测到 ICS 服务运行
	Diagnostic string         `json:"diagnostic"` // 综合诊断报告建议
}

// PortChecker 定义端口冲突探测接口
type PortChecker interface {
	CheckPort53(ctx context.Context) (*PortCheckResult, error)
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
	return testUDPBind("127.0.0.1:53") && testTCPBind("127.0.0.1:53")
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

// CheckPort53 探测 53 端口冲突并识别 SharedAccess (ICS) 等服务（基于 Windows 原生 Win32 API）
func (c *WindowsPortChecker) CheckPort53(ctx context.Context) (*PortCheckResult, error) {
	// 1. 本地尝试轻量级绑定探测（检测当前用户态能否直接成功监听 127.0.0.1:53）
	udpFree := testUDPBind("127.0.0.1:53")
	tcpFree := testTCPBind("127.0.0.1:53")
	available := udpFree && tcpFree

	// 2. 通过 Windows 原生 API 深度检测全系统 53 端口监听实体及 ICS 状态
	conflicts, hasICS, diag, err := checkPort53Native(available, os.Getpid())
	if err != nil {
		return &PortCheckResult{
			Available:  available,
			Conflicts:  nil,
			HasICS:     false,
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

	// 端口可用性判定：
	// 1. 若检测到外部冲突进程或 ICS 正在运行，判定为不可用 (false)
	// 2. 若套接字绑定探测失败，且非本服务自身监听中，判定为不可用 (false)
	// 3. 仅当无外部冲突、无 ICS，且（套接字可正常绑定 或 当前已被本进程占用）时判定为可用
	if hasOtherConflict || hasICS {
		available = false
	} else if !udpFree || !tcpFree {
		if !hasSelfListener {
			available = false
		}
	} else {
		available = true
	}

	return &PortCheckResult{
		Available:  available,
		Conflicts:  conflicts,
		HasICS:     hasICS,
		Diagnostic: diag,
	}, nil
}

func testUDPBind(addr string) bool {
	conn, err := net.ListenPacket("udp4", addr)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func testTCPBind(addr string) bool {
	l, err := net.Listen("tcp4", addr)
	if err != nil {
		return false
	}
	_ = l.Close()
	return true
}

func ternary[T any](cond bool, a, b T) T {
	if cond {
		return a
	}
	return b
}
