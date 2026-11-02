//go:build windows

package windows

import (
	"context"
	"fmt"
	"os"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// WindowsPortChecker Windows 平台 53 端口占用与冲突检测器。
type WindowsPortChecker struct {
	executor platform.CommandExecutor
}

// NewPortChecker 创建端口检测器。
func NewPortChecker(executor platform.CommandExecutor) *WindowsPortChecker {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	return &WindowsPortChecker{executor: executor}
}

// CheckPort53 探测默认回环地址 (127.0.0.1:53) 的端口冲突状况
func (c *WindowsPortChecker) CheckPort53(ctx context.Context) (*platform.PortCheckResult, error) {
	return c.CheckPort53ForAddresses(ctx, []string{"127.0.0.1:53"}, []string{"127.0.0.1:53"})
}

// CheckPort53ForAddresses 针对实际配置的目标双栈 UDP 与 TCP 监听地址执行精准探测
// 遵循 AdGuard Home 的 Real Socket Check 原则：以实际目标套接字探测结果为准。
func (c *WindowsPortChecker) CheckPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*platform.PortCheckResult, error) {
	if len(udpAddrs) == 0 && len(tcpAddrs) == 0 {
		udpAddrs = []string{"127.0.0.1:53"}
		tcpAddrs = []string{"127.0.0.1:53"}
	}

	// 1. 本地尝试对所有目标地址进行轻量级绑定探测（Real Socket Check）
	socketsFree := platform.AreAddressesAvailable(udpAddrs, tcpAddrs)

	// 2. 通过 Windows 原生 API 深度检测全系统 53 端口监听实体及 ICS 状态
	conflicts, hasICS, diag, err := checkPort53Native(socketsFree, os.Getpid())
	if err != nil {
		return &platform.PortCheckResult{
			Available:  socketsFree,
			Conflicts:  nil,
			HasICS:     false,
			CanAutofix: false,
			Diagnostic: fmt.Sprintf("53 端口套接字绑定探测: %v (原生诊断失败: %v)", socketsFree, err),
		}, nil
	}

	return evaluatePortAvailability(socketsFree, conflicts, hasICS, diag, udpAddrs, tcpAddrs), nil
}

// evaluatePortAvailability 汇总套接字探测结果与系统监听实体，判定端口真实可用性与自动修复资格。
func evaluatePortAvailability(socketsFree bool, conflicts []platform.PortConflict, hasICS bool, diag string, udpAddrs, tcpAddrs []string) *platform.PortCheckResult {
	hasThirdPartyConflict := false
	hasSelfListener := false
	for _, conf := range conflicts {
		if conf.IsSelf {
			hasSelfListener = true
		} else if !conf.IsICS {
			hasThirdPartyConflict = true
		}
	}

	// 3. 依据 Real Socket Check 判定目标地址真实可用性与 Autofix 资格：
	// - 若目标套接字绑定成功（socketsFree），或当前已被自身 PID 监听，则 available = true；
	// - 若当前仅监听回环 (127.0.0.1)，且套接字真实测试绑定成功，不因后台存在 ICS 服务而一票否决；
	// - 若套接字绑定失败（!socketsFree），且检测到 ICS 正在运行且无第三方冲突，判定为不可用且 canAutofix = true；
	// - 若存在第三方程序占用，判定为不可用且 canAutofix = false。
	available := false
	canAutofix := false

	if socketsFree || hasSelfListener {
		available = true
		canAutofix = false
	} else {
		available = false
		if hasICS && !hasThirdPartyConflict {
			canAutofix = true
			if !platform.IsOnlyLoopback(udpAddrs, tcpAddrs) {
				diag = fmt.Sprintf("当前启用了局域网共享监听 (0.0.0.0:53)，检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行并占用了 0.0.0.0:53。\n排查建议：点击【一键自动修复并启动】自动停止并禁用 ICS 服务，或关闭局域网共享模式降级为仅本机回环监听。\n%s", diag)
			} else {
				diag = fmt.Sprintf("53 端口套接字绑定失败。检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行。\n排查建议：点击【一键自动修复并启动】自动停止并禁用 ICS 服务后重试。\n%s", diag)
			}
		} else if hasICS && hasThirdPartyConflict {
			canAutofix = false
			diag = fmt.Sprintf("53 端口同时被 Windows 网络连接共享服务 (SharedAccess / ICS) 与第三方外部程序占用。\n排查建议：需先在任务管理器中关闭占用 53 端口的外部程序并停止 ICS 服务。\n%s", diag)
		} else if hasThirdPartyConflict {
			canAutofix = false
		}
	}

	return &platform.PortCheckResult{
		Available:  available,
		Conflicts:  conflicts,
		HasICS:     hasICS,
		CanAutofix: canAutofix,
		Diagnostic: diag,
	}
}

// FallbackPortConflict 在无法执行深度原生诊断时，构造一份通用冲突结果与错误。
func FallbackPortConflict(err error) *platform.PortConflictError {
	return &platform.PortConflictError{
		Result: &platform.PortCheckResult{
			Available:  false,
			Diagnostic: "本地 53 端口已被占用，无法启动 DNS 监听器。排查建议：请检查是否有其他 DNS 或代理软件占用该端口。",
		},
		Err: err,
	}
}

// ternary 泛型三目辅助函数，用于简化条件赋值。
func ternary[T any](cond bool, a, b T) T {
	if cond {
		return a
	}
	return b
}
