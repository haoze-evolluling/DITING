//go:build linux

package linux

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// LinuxPortChecker Linux 平台 53 端口占用与冲突检测器。
//
// 探测方式与 Windows 版一致地遵循 AdGuard Home 的 Real Socket Check 原则：
// 以实际目标套接字的绑定结果为准，再结合 /proc/net 解析出的监听实体给出诊断。
type LinuxPortChecker struct {
	executor platform.CommandExecutor
}

// NewPortChecker 创建端口检测器。
func NewPortChecker(executor platform.CommandExecutor) *LinuxPortChecker {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	return &LinuxPortChecker{executor: executor}
}

// CheckPort53 探测默认回环地址 (127.0.0.1:53) 的端口冲突状况。
func (c *LinuxPortChecker) CheckPort53(ctx context.Context) (*platform.PortCheckResult, error) {
	return c.CheckPort53ForAddresses(ctx, []string{"127.0.0.1:53"}, []string{"127.0.0.1:53"})
}

// CheckPort53ForAddresses 针对实际配置的目标双栈 UDP 与 TCP 监听地址执行精准探测。
func (c *LinuxPortChecker) CheckPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*platform.PortCheckResult, error) {
	if len(udpAddrs) == 0 && len(tcpAddrs) == 0 {
		udpAddrs = []string{"127.0.0.1:53"}
		tcpAddrs = []string{"127.0.0.1:53"}
	}

	// 1. Real Socket Check：本地尝试绑定所有目标地址
	socketsFree := platform.AreAddressesAvailable(udpAddrs, tcpAddrs)

	// 2. 解析 /proc/net 定位实际监听 53 端口的实体
	conflicts, hasStub, diag, err := inspectPort53Listeners()
	if err != nil {
		return &platform.PortCheckResult{
			Available:  socketsFree,
			CanAutofix: false,
			Diagnostic: fmt.Sprintf("53 端口套接字绑定探测: %v (/proc 诊断失败: %v)", socketsFree, err),
		}, nil
	}

	return evaluateLinuxPortAvailability(socketsFree, conflicts, hasStub, diag, udpAddrs, tcpAddrs), nil
}

// inspectPort53Listeners 解析系统 53 端口监听实体，识别 systemd-resolved stub 占用。
func inspectPort53Listeners() (conflicts []platform.PortConflict, hasStub bool, diag string, err error) {
	sockets, err := collectPort53Sockets()
	if err != nil {
		return nil, false, "", err
	}
	if len(sockets) == 0 {
		return nil, false, "53 端口当前空闲且可用。", nil
	}

	owners := socketInodeOwners()
	selfPID := os.Getpid()
	resolvedPID := systemdResolvedPID()

	var diagLines []string
	seen := make(map[string]bool)

	for _, s := range sockets {
		key := s.Protocol + "|" + s.LocalAddress
		if seen[key] {
			continue
		}
		seen[key] = true

		pid := owners[s.Inode]
		name := processName(pid)
		isSelf := pid == selfPID
		isStub := isResolvedStubAddress(s.LocalAddress) ||
			(resolvedPID != 0 && pid == resolvedPID) ||
			isSystemdResolvedProcess(pid)

		conflict := platform.PortConflict{
			Port:         53,
			Protocol:     s.Protocol,
			LocalAddress: s.LocalAddress,
			PID:          pid,
			ProcessName:  name,
			IsICS:        isStub,
			IsSelf:       isSelf,
		}

		switch {
		case isSelf:
			conflict.Diagnosis = "谛听 (DITING) 核心服务监听中。"
			diagLines = append(diagLines, "谛听 (DITING) 核心服务正在监听 "+s.LocalAddress)
		case isStub:
			hasStub = true
			conflict.ServiceName = "systemd-resolved"
			conflict.Diagnosis = "systemd-resolved 的 stub 监听器占用了该地址，会阻止本地 DNS 代理绑定 127.0.0.53:53。"
			diagLines = append(diagLines, fmt.Sprintf(
				"检测到 systemd-resolved stub 监听器占用 %s (PID: %d)。systemd-resolved 默认在 127.0.0.53:53 与 127.0.0.54:53 上提供本地存根解析。",
				s.LocalAddress, pid))
		case pid != 0:
			conflict.Diagnosis = fmt.Sprintf("被外部进程 %s (PID: %d) 占用，需先停止该进程再启动谛听 DNS 服务。", name, pid)
			diagLines = append(diagLines, fmt.Sprintf("外部程序 %s (PID: %d) 正在占用 %s。", name, pid, s.LocalAddress))
		default:
			conflict.Diagnosis = "占用进程无法定位（可能属于其他用户或已退出），请使用 sudo ss -lunpt 进一步排查。"
			diagLines = append(diagLines, fmt.Sprintf("%s 被未知进程占用。", s.LocalAddress))
		}

		conflicts = append(conflicts, conflict)
	}

	sort.Slice(conflicts, func(i, j int) bool {
		if conflicts[i].Protocol != conflicts[j].Protocol {
			return conflicts[i].Protocol < conflicts[j].Protocol
		}
		return conflicts[i].LocalAddress < conflicts[j].LocalAddress
	})

	return conflicts, hasStub, strings.Join(diagLines, "\n"), nil
}

// evaluateLinuxPortAvailability 汇总套接字探测结果与系统监听实体，判定可用性与自动修复资格。
//
// 语义与 Windows 版 evaluatePortAvailability 保持一致：
// 套接字绑定成功或被自身监听即视为可用；仅被可自动修复的系统级占用（此处为
// systemd-resolved stub）阻塞时标记 CanAutofix；存在第三方占用时不可自动修复。
func evaluateLinuxPortAvailability(socketsFree bool, conflicts []platform.PortConflict, hasStub bool, diag string, udpAddrs, tcpAddrs []string) *platform.PortCheckResult {
	hasThirdPartyConflict := false
	hasSelfListener := false
	for _, conf := range conflicts {
		if conf.IsSelf {
			hasSelfListener = true
		} else if !conf.IsICS {
			hasThirdPartyConflict = true
		}
	}

	available := false
	canAutofix := false

	if socketsFree || hasSelfListener {
		available = true
		canAutofix = false
	} else {
		available = false
		switch {
		case hasStub && !hasThirdPartyConflict:
			canAutofix = true
			if !platform.IsOnlyLoopback(udpAddrs, tcpAddrs) {
				diag = fmt.Sprintf("当前启用了局域网共享监听 (0.0.0.0:53)，但 systemd-resolved 的 stub 监听器占用了本机 53 端口。\n排查建议：点击【一键自动修复并启动】关闭 systemd-resolved 的 DNSStubListener 并重启该服务，或关闭局域网共享模式降级为仅本机回环监听。\n%s", diag)
			} else {
				diag = fmt.Sprintf("53 端口套接字绑定失败，systemd-resolved 的 stub 监听器正在运行。\n排查建议：点击【一键自动修复并启动】写入 /etc/systemd/resolved.conf.d/diting.conf 并设置 DNSStubListener=no，随后重启 systemd-resolved。\n%s", diag)
			}
		case hasStub && hasThirdPartyConflict:
			canAutofix = false
			diag = fmt.Sprintf("53 端口同时被 systemd-resolved 与第三方外部程序占用。\n排查建议：请先用 sudo ss -lunpt | grep :53 定位并停止外部程序，再处理 systemd-resolved。\n%s", diag)
		case hasThirdPartyConflict:
			canAutofix = false
		}
	}

	return &platform.PortCheckResult{
		Available:  available,
		Conflicts:  conflicts,
		HasICS:     hasStub,
		CanAutofix: canAutofix,
		Diagnostic: diag,
	}
}

// FallbackPortConflict 在无法执行深度诊断时，构造一份通用冲突结果与错误。
func FallbackPortConflict(err error) *platform.PortConflictError {
	return &platform.PortConflictError{
		Result: &platform.PortCheckResult{
			Available:  false,
			Diagnostic: "本地 53 端口已被占用，无法启动 DNS 监听器。排查建议：请执行 sudo ss -lunpt | grep :53 检查占用程序。",
		},
		Err: err,
	}
}
