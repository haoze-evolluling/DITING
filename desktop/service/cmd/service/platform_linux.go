//go:build linux

package main

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/platform"
	"github.com/haoze-evolluling/diting/server/internal/platform/linux"
)

// newDNSManager 构造当前平台（Linux）的 DNS 接管管理器。
func newDNSManager(exec platform.CommandExecutor, store platform.StateStore, version string) platform.DNSManager {
	return linux.NewDNSManager(exec, store, version)
}

// newAdapterScanner 构造当前平台（Linux）的网卡枚举扫描器。
func newAdapterScanner(exec platform.CommandExecutor) platform.AdapterScanner {
	return linux.NewAdapterScanner(exec)
}

// newPortChecker 构造当前平台（Linux）的端口冲突探测器。
func newPortChecker(exec platform.CommandExecutor) platform.PortChecker {
	return linux.NewPortChecker(exec)
}

// newServiceManager 构造当前平台（Linux）的后台核心服务管理器。
func newServiceManager(exec platform.CommandExecutor) platform.ServiceManager {
	return linux.NewServiceManager(exec, nil)
}

// firewallCheckPort53 检测 53 端口防火墙放行规则是否生效。
func firewallCheckPort53(ctx context.Context) (bool, error) {
	return linux.CheckFirewallPort53(ctx, platform.NewDefaultExecutor())
}

// firewallConfigurePort53 配置 53 端口防火墙放行规则。
func firewallConfigurePort53(ctx context.Context, enable bool) error {
	return linux.ConfigureFirewallPort53(ctx, platform.NewDefaultExecutor(), enable)
}

// firewallCheckWeb 检测 Web 管理端口防火墙放行规则是否生效。
func firewallCheckWeb(ctx context.Context) (bool, error) {
	return linux.CheckFirewallPortWeb(ctx, platform.NewDefaultExecutor())
}

// firewallConfigureWeb 配置 Web 管理端口防火墙放行规则。
func firewallConfigureWeb(ctx context.Context, port int, enable bool) error {
	return linux.ConfigureFirewallPortWeb(ctx, platform.NewDefaultExecutor(), port, enable)
}

// firewallBackendName 返回探测到的防火墙后端名称（"none" 表示未检测到任何管理器）。
func firewallBackendName() string {
	return linux.FirewallBackendName()
}

// platformDisplayName 返回当前平台的可读名称，用于版本与诊断输出。
func platformDisplayName() string {
	return "Linux"
}

// defaultServiceConfig 返回当前平台的默认服务配置（服务名、显示名与描述）。
func defaultServiceConfig() (name, displayName, description string) {
	return "diting-dnsservice",
		"谛听 DNS 内核特权服务",
		"谛听 Linux 端 DNS 内核特权服务，负责系统 DNS 接管与多协议上游转发。"
}

// privilegedPortCheckHint 返回端口诊断输出中针对系统级占用的提示前缀。
func privilegedPortCheckHint() string {
	return "是否检测到 systemd-resolved stub"
}
