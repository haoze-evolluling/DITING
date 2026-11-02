//go:build linux

package linux

import (
	"context"
	"fmt"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// firewallManager 标识探测到的防火墙管理后端。
type firewallManager int

const (
	firewallNone firewallManager = iota
	firewallFirewalld
	firewallUfw
	firewallNftables
	firewallIptables
)

// String 返回防火墙后端的可读名称。
func (m firewallManager) String() string {
	switch m {
	case firewallFirewalld:
		return "firewalld"
	case firewallUfw:
		return "ufw"
	case firewallNftables:
		return "nftables"
	case firewallIptables:
		return "iptables"
	default:
		return "none"
	}
}

// detectFirewallManager 按优先级探测可用的防火墙管理后端。
//
// 探测顺序：firewalld → ufw → nftables → iptables。
// 全部缺失时返回 firewallNone，由调用方走诊断降级路径。
func detectFirewallManager() firewallManager {
	switch {
	case commandExists("firewall-cmd"):
		return firewallFirewalld
	case commandExists("ufw"):
		return firewallUfw
	case commandExists("nft"):
		return firewallNftables
	case commandExists("iptables"):
		return firewallIptables
	default:
		return firewallNone
	}
}

// FirewallBackendName 返回探测到的防火墙后端名称。
//
// 取值为 "firewalld" / "ufw" / "nftables" / "iptables"；系统未安装任何防火墙
// 管理器时返回 "none"——此时端口本就对外开放，调用方应跳过放行操作，
// 而不是把"无需放行"当成错误呈现。
func FirewallBackendName() string {
	return detectFirewallManager().String()
}

// CheckFirewallPort53 检测 53 端口 (UDP 与 TCP) 入站放行规则是否存在。
//
// 未探测到任何防火墙管理器时返回 false 与 nil 错误——
// 在无防火墙的系统中端口本身即对外开放，无需额外放行。
func CheckFirewallPort53(ctx context.Context, executor platform.CommandExecutor) (bool, error) {
	mgr := detectFirewallManager()
	if mgr == firewallNone {
		return false, nil
	}
	udp, err := checkFirewallRuleForPort(ctx, executor, mgr, 53, "udp")
	if err != nil || !udp {
		return false, err
	}
	tcp, err := checkFirewallRuleForPort(ctx, executor, mgr, 53, "tcp")
	if err != nil {
		return false, err
	}
	return tcp, nil
}

// ConfigureFirewallPort53 配置 53 端口 (UDP 与 TCP) 的入站放行规则。
//
// 未探测到任何防火墙管理器时返回 platform.Unsupported——调用方应先经
// FirewallBackendName 判断，为 "none" 时跳过本调用，避免把"无需放行"记为错误。
func ConfigureFirewallPort53(ctx context.Context, executor platform.CommandExecutor, enable bool) error {
	mgr := detectFirewallManager()
	if mgr == firewallNone {
		return platform.Unsupported("配置 53 端口防火墙规则（未检测到 firewalld / ufw / nftables / iptables）")
	}

	if err := configureFirewallRuleForPort(ctx, executor, mgr, 53, "udp", enable); err != nil {
		return err
	}
	return configureFirewallRuleForPort(ctx, executor, mgr, 53, "tcp", enable)
}

// CheckFirewallPortWeb 检测 Web 管理端口的入站放行规则是否存在。
func CheckFirewallPortWeb(ctx context.Context, executor platform.CommandExecutor) (bool, error) {
	mgr := detectFirewallManager()
	if mgr == firewallNone {
		return false, nil
	}
	return checkFirewallRuleForPort(ctx, executor, mgr, defaultWebPort, "tcp")
}

// ConfigureFirewallPortWeb 配置 Web 管理端口的入站放行规则。
//
// 未探测到任何防火墙管理器时返回 platform.Unsupported——调用方应先经
// FirewallBackendName 判断，为 "none" 时跳过本调用，避免把"无需放行"记为错误。
func ConfigureFirewallPortWeb(ctx context.Context, executor platform.CommandExecutor, port int, enable bool) error {
	if port <= 0 {
		port = defaultWebPort
	}
	mgr := detectFirewallManager()
	if mgr == firewallNone {
		return platform.Unsupported("配置 Web 管理端口防火墙规则（未检测到 firewalld / ufw / nftables / iptables）")
	}
	return configureFirewallRuleForPort(ctx, executor, mgr, port, "tcp", enable)
}

// defaultWebPort 为 Web 管理控制台默认监听端口。
const defaultWebPort = 15353

// checkFirewallRuleForPort 按防火墙后端查询指定协议端口的放行状态。
func checkFirewallRuleForPort(ctx context.Context, executor platform.CommandExecutor, mgr firewallManager, port int, proto string) (bool, error) {
	switch mgr {
	case firewallFirewalld:
		out, err := runCommand(ctx, executor, "firewall-cmd", "--query-port", fmt.Sprintf("%d/%s", port, proto))
		if err != nil {
			return false, nil
		}
		return strings.Contains(strings.ToLower(out), "yes"), nil
	case firewallUfw:
		out, err := runCommand(ctx, executor, "ufw", "status")
		if err != nil {
			return false, nil
		}
		return ufwRulePresent(out, port, proto), nil
	case firewallIptables:
		out, err := runCommand(ctx, executor, iptablesBinary(proto), "-S", "INPUT")
		if err != nil {
			return false, nil
		}
		return strings.Contains(out, fmt.Sprintf("--dport %d", port)), nil
	case firewallNftables:
		// nftables 的规则集为复杂规则语言，无法可靠地做单规则精确匹配，
		// 统一交由配置路径保证幂等；此处仅报告"未知"。
		return false, nil
	default:
		return false, nil
	}
}

// configureFirewallRuleForPort 按防火墙后端增删指定协议端口的放行规则。
func configureFirewallRuleForPort(ctx context.Context, executor platform.CommandExecutor, mgr firewallManager, port int, proto string, enable bool) error {
	switch mgr {
	case firewallFirewalld:
		op := "--add-port"
		if !enable {
			op = "--remove-port"
		}
		_, err := runCommand(ctx, executor, "firewall-cmd", "--permanent", op, fmt.Sprintf("%d/%s", port, proto))
		if err != nil {
			return fmt.Errorf("firewalld 配置 %d/%s 失败: %w", port, proto, err)
		}
		_, err = runCommand(ctx, executor, "firewall-cmd", "--reload")
		return err
	case firewallUfw:
		if enable {
			_, err := runCommand(ctx, executor, "ufw", "allow", fmt.Sprintf("%d/%s", port, proto))
			return err
		}
		_, err := runCommand(ctx, executor, "ufw", "delete", "allow", fmt.Sprintf("%d/%s", port, proto))
		return err
	case firewallIptables:
		return configureIptablesRule(ctx, executor, port, proto, enable)
	case firewallNftables:
		return configureNftRule(ctx, executor, port, proto, enable)
	default:
		return platform.Unsupported("配置防火墙规则")
	}
}

// configureIptablesRule 直接操作 iptables INPUT 链（重启后不保留，属尽力而为的放行）。
func configureIptablesRule(ctx context.Context, executor platform.CommandExecutor, port int, proto string, enable bool) error {
	op := "-A"
	if !enable {
		op = "-D"
	}
	args := []string{op, "INPUT", "-p", proto, "--dport", fmt.Sprint(port), "-j", "ACCEPT"}
	_, err := runCommand(ctx, executor, iptablesBinary(proto), args...)
	if err != nil && !enable {
		// 删除不存在的规则会报错，此处忽略以保证幂等
		return nil
	}
	if err != nil {
		return fmt.Errorf("iptables 配置 %d/%s 失败: %w", port, proto, err)
	}
	return nil
}

// configureNftRule 创建/销毁独立的 diting 表，避免污染用户既有规则集。
func configureNftRule(ctx context.Context, executor platform.CommandExecutor, port int, proto string, enable bool) error {
	if !enable {
		_, err := runCommand(ctx, executor, "nft", "delete", "table", "inet", "diting")
		if err != nil {
			// 表不存在时删除会报错，忽略以保证幂等
			return nil
		}
		return nil
	}

	script := fmt.Sprintf(
		"nft 'add table inet diting' 2>/dev/null; "+
			"nft 'add chain inet diting input { type filter hook input priority 0; }' 2>/dev/null; "+
			"nft 'add rule inet diting input %s dport %d accept' 2>/dev/null; true",
		proto, port,
	)
	if _, err := runCommand(ctx, executor, "sh", "-c", script); err != nil {
		return fmt.Errorf("nftables 配置 %d/%s 失败: %w", port, proto, err)
	}
	return nil
}

// iptablesBinary 返回协议对应的 iptables 可执行文件（IPv6 使用 ip6tables）。
func iptablesBinary(proto string) string {
	if strings.HasSuffix(proto, "6") {
		return "ip6tables"
	}
	return "iptables"
}

// ufwRulePresent 判断 ufw status 输出中是否已放行指定端口。
func ufwRulePresent(statusOut string, port int, proto string) bool {
	target := fmt.Sprintf("%d/%s", port, proto)
	for _, line := range strings.Split(statusOut, "\n") {
		lower := strings.ToLower(strings.TrimSpace(line))
		if strings.HasPrefix(lower, target) && strings.Contains(lower, "allow") {
			return true
		}
	}
	return false
}
