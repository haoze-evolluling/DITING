//go:build windows

package main

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/platform"
	"github.com/haoze-evolluling/diting/server/internal/platform/windows"
)

// newDNSManager 构造当前平台（Windows）的 DNS 接管管理器。
func newDNSManager(exec platform.CommandExecutor, store platform.StateStore, version string) platform.DNSManager {
	return windows.NewDNSManager(exec, store, version)
}

// newAdapterScanner 构造当前平台（Windows）的网卡枚举扫描器。
func newAdapterScanner(exec platform.CommandExecutor) platform.AdapterScanner {
	return windows.NewAdapterScanner(exec)
}

// newPortChecker 构造当前平台（Windows）的端口冲突探测器。
func newPortChecker(exec platform.CommandExecutor) platform.PortChecker {
	return windows.NewPortChecker(exec)
}

// newServiceManager 构造当前平台（Windows）的后台核心服务管理器。
//
// 以 nil 传入特权执行器：服务进程自身即以 LocalSystem 运行，
// 状态查询无需提权，也不会触发 UAC 弹窗。
func newServiceManager(exec platform.CommandExecutor) platform.ServiceManager {
	return windows.NewServiceManager(exec, nil)
}

// firewallCheckPort53 检测 53 端口防火墙放行规则是否生效。
func firewallCheckPort53(ctx context.Context) (bool, error) {
	return windows.CheckFirewallPort53(ctx, platform.NewDefaultExecutor())
}

// firewallConfigurePort53 配置 53 端口防火墙放行规则。
func firewallConfigurePort53(ctx context.Context, enable bool) error {
	return windows.ConfigureFirewallPort53(ctx, platform.NewDefaultExecutor(), enable)
}

// firewallCheckWeb 检测 Web 管理端口防火墙放行规则是否生效。
func firewallCheckWeb(ctx context.Context) (bool, error) {
	return windows.CheckFirewallPortWeb(ctx, platform.NewDefaultExecutor())
}

// firewallConfigureWeb 配置 Web 管理端口防火墙放行规则。
func firewallConfigureWeb(ctx context.Context, port int, enable bool) error {
	return windows.ConfigureFirewallPortWeb(ctx, platform.NewDefaultExecutor(), port, enable)
}

// firewallBackendName 返回防火墙后端名称。
//
// Windows 始终由 Defender 防火墙托管，恒为可用，返回固定标识 "windows"。
func firewallBackendName() string {
	return "windows"
}

// platformDisplayName 返回当前平台的可读名称，用于版本与诊断输出。
func platformDisplayName() string {
	return "Windows"
}

// defaultServiceConfig 返回当前平台的默认服务配置（服务名、显示名与描述）。
func defaultServiceConfig() (name, displayName, description string) {
	return "DitingDNSService",
		"谛听 DNS 内核特权服务",
		"谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。"
}

// privilegedPortCheckHint 返回端口诊断输出中针对系统级占用的提示前缀。
func privilegedPortCheckHint() string {
	return "是否检测到 ICS (SharedAccess)"
}
