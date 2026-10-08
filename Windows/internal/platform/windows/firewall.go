package windows

import (
	"context"
	"fmt"
	"strings"
)

const (
	// FirewallRuleNameUDP 谛听局域网 DNS UDP 防火墙入站规则名称
	FirewallRuleNameUDP = "Diting DNS LAN Server (UDP)"
	// FirewallRuleNameTCP 谛听局域网 DNS TCP 防火墙入站规则名称
	FirewallRuleNameTCP = "Diting DNS LAN Server (TCP)"
)

// CheckFirewallPort53 检测 Windows 防火墙是否已放行 53 端口入站规则 (UDP 与 TCP 均需已启用且操作为允许)
func CheckFirewallPort53(ctx context.Context, executor CommandExecutor) (bool, error) {
	if executor == nil {
		executor = NewDefaultExecutor()
	}

	outUDP, err := executor.RunCommand(ctx, "netsh", "advfirewall", "firewall", "show", "rule", fmt.Sprintf("name=%s", FirewallRuleNameUDP))
	if err != nil || !isFirewallRuleActive(outUDP) {
		return false, nil
	}

	outTCP, err := executor.RunCommand(ctx, "netsh", "advfirewall", "firewall", "show", "rule", fmt.Sprintf("name=%s", FirewallRuleNameTCP))
	if err != nil || !isFirewallRuleActive(outTCP) {
		return false, nil
	}

	return true, nil
}

func isFirewallRuleActive(out string) bool {
	lines := strings.Split(out, "\n")
	enabled := false
	actionAllow := false
	for _, rawLine := range lines {
		line := strings.TrimSpace(rawLine)
		lower := strings.ToLower(line)
		if strings.HasPrefix(lower, "enabled:") || strings.HasPrefix(line, "已启用:") {
			if strings.Contains(lower, "yes") || strings.Contains(line, "是") {
				enabled = true
			} else {
				enabled = false
			}
		}
		if strings.HasPrefix(lower, "action:") || strings.HasPrefix(line, "操作:") {
			if strings.Contains(lower, "allow") || strings.Contains(line, "允许") {
				actionAllow = true
			} else {
				actionAllow = false
			}
		}
	}
	return enabled && actionAllow
}

// ConfigureFirewallPort53 配置 Windows 防火墙允许或禁止局域网访问 53 端口 (UDP 与 TCP)
func ConfigureFirewallPort53(ctx context.Context, executor CommandExecutor, enable bool) error {
	if executor == nil {
		executor = NewDefaultExecutor()
	}

	// 无论开启还是关闭，先清理已存在的旧规则以确保操作幂等性
	_ = deleteFirewallRule(ctx, executor, FirewallRuleNameUDP)
	_ = deleteFirewallRule(ctx, executor, FirewallRuleNameTCP)
	_ = deleteFirewallRule(ctx, executor, "Diting DNS LAN Server") // 兼容历史单条命名

	if !enable {
		return nil
	}

	// 添加 UDP 53 入站放行规则
	if out, err := executor.RunCommand(ctx, "netsh", "advfirewall", "firewall", "add", "rule",
		fmt.Sprintf("name=%s", FirewallRuleNameUDP),
		"dir=in",
		"action=allow",
		"protocol=UDP",
		"localport=53",
		"profile=any",
		`description=谛听 DNS 局域网服务 UDP 端口放行`,
	); err != nil {
		return fmt.Errorf("添加 UDP 53 防火墙规则失败: %s (%w)", strings.TrimSpace(out), err)
	}

	// 添加 TCP 53 入站放行规则
	if out, err := executor.RunCommand(ctx, "netsh", "advfirewall", "firewall", "add", "rule",
		fmt.Sprintf("name=%s", FirewallRuleNameTCP),
		"dir=in",
		"action=allow",
		"protocol=TCP",
		"localport=53",
		"profile=any",
		`description=谛听 DNS 局域网服务 TCP 端口放行`,
	); err != nil {
		return fmt.Errorf("添加 TCP 53 防火墙规则失败: %s (%w)", strings.TrimSpace(out), err)
	}

	return nil
}

func deleteFirewallRule(ctx context.Context, executor CommandExecutor, ruleName string) error {
	_, err := executor.RunCommand(ctx, "netsh", "advfirewall", "firewall", "delete", "rule", fmt.Sprintf("name=%s", ruleName))
	return err
}
