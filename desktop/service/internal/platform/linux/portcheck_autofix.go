//go:build linux

package linux

import (
	"context"
	"errors"
	"fmt"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// AutofixPort53ForAddresses 自动修复 53 端口冲突并重新校验可用性。
//
// 目前唯一可安全自动修复的系统级冲突为 systemd-resolved 的 stub 监听器：
// 写入 DNSStubListener=no 的 drop-in 配置并重启 systemd-resolved，
// 从而释放 127.0.0.53:53 与 127.0.0.54:53。第三方程序占用不在此处理范围内。
func (c *LinuxPortChecker) AutofixPort53ForAddresses(ctx context.Context, udpAddrs, tcpAddrs []string) (*platform.PortCheckResult, error) {
	if len(udpAddrs) == 0 && len(tcpAddrs) == 0 {
		udpAddrs = []string{"127.0.0.1:53"}
		tcpAddrs = []string{"127.0.0.1:53"}
	}

	before, err := c.CheckPort53ForAddresses(ctx, udpAddrs, tcpAddrs)
	if err != nil {
		return before, err
	}
	if before.Available {
		return before, nil
	}
	if !before.HasICS {
		return before, fmt.Errorf("检测到第三方程序占用 53 端口，无法自动修复，请手动停止相关进程")
	}

	if err := disableResolvedStubListener(ctx, c.executor); err != nil {
		return before, fmt.Errorf("自动修复 systemd-resolved stub 监听失败: %w", err)
	}

	after, err := c.CheckPort53ForAddresses(ctx, udpAddrs, tcpAddrs)
	if err != nil {
		return after, err
	}
	if after.Available {
		after.Diagnostic = "已成功关闭 systemd-resolved 的 stub 监听器，53 端口现已可用。\n" + after.Diagnostic
		return after, nil
	}
	// 修复动作执行完但端口仍被占用：必须报错，否则上层会当成「已修复」静默继续
	return after, fmt.Errorf("已关闭 systemd-resolved stub 监听器，但 53 端口仍不可用，请查看诊断信息")
}

// disableResolvedStubListener 写入 DNSStubListener=no 并重启 systemd-resolved。
func disableResolvedStubListener(ctx context.Context, executor platform.CommandExecutor) error {
	if !resolvedDropInSupported() {
		return errors.New("无法创建 /etc/systemd/resolved.conf.d 目录，请以 root 身份运行")
	}

	if err := writeFileMode(resolvedDropFile, []byte(resolvedDropInContent), 0o644); err != nil {
		return fmt.Errorf("写入 %s 失败: %w", resolvedDropFile, err)
	}

	if _, err := runCommand(ctx, executor, "systemctl", "restart", "systemd-resolved"); err != nil {
		// 部分 WSL/容器环境无 systemd 单元，回退尝试直接终止 stub 进程
		if fallbackErr := stopResolvedStubProcess(ctx, executor); fallbackErr != nil {
			return fmt.Errorf("重启 systemd-resolved 失败 (%v)，且回退停止 stub 亦失败: %w（已写入 %s，卸载谛听后请手动删除）", err, fallbackErr, resolvedDropFile)
		}
	}
	return nil
}

// resolvedDropInContent 为关闭 stub 监听的 drop-in 配置内容。
const resolvedDropInContent = `# 由谛听 (DITING) 写入：关闭 systemd-resolved 的本地 stub 监听器，
# 释放 127.0.0.53:53 与 127.0.0.54:53 供谛听 DNS 服务绑定。
# 卸载谛听服务后可安全删除本文件并执行 systemctl restart systemd-resolved。
[Resolve]
DNSStubListener=no
`

// stopResolvedStubProcess 在无 systemd 单元时直接终止 stub 进程作为兜底。
func stopResolvedStubProcess(ctx context.Context, executor platform.CommandExecutor) error {
	pid := systemdResolvedPID()
	// 找不到进程不是「无需处理」而是「无法处理」：返回 nil 会让调用方
	// 把一次没生效的自愈当成成功（drop-in 已写入、stub 仍在监听）。
	if pid == 0 {
		return errors.New("未能定位 systemd-resolved 进程，无法终止 stub 监听器")
	}
	if !isSystemdResolvedProcess(pid) {
		return fmt.Errorf("PID %d 不是 systemd-resolved 进程，拒绝终止", pid)
	}
	_, err := runCommand(ctx, executor, "kill", "-TERM", fmt.Sprint(pid))
	return err
}
