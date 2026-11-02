//go:build linux

package linux

import (
	"context"
	"os"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// dnsBackendKind 标识当前系统所用的 DNS 配置后端。
type dnsBackendKind int

const (
	// backendNone 表示未探测到任何可管理的 DNS 后端。
	backendNone dnsBackendKind = iota
	// backendSystemdResolved 使用 systemd-resolved (resolvectl) 管理解析。
	backendSystemdResolved
	// backendNetworkManager 使用 NetworkManager (nmcli) 管理连接级 DNS。
	backendNetworkManager
	// backendResolvConf 直接管理 /etc/resolv.conf 静态文件。
	backendResolvConf
)

// String 返回后端的可读名称。
func (k dnsBackendKind) String() string {
	switch k {
	case backendSystemdResolved:
		return "systemd-resolved"
	case backendNetworkManager:
		return "NetworkManager"
	case backendResolvConf:
		return "resolv.conf"
	default:
		return "none"
	}
}

// dnsBackend 抽象一种系统 DNS 配置后端。
//
// 每个后端需实现"接管（将系统解析指向本机）"与"还原（恢复接管前快照）"，
// 并保证 Apply 失败时不留下半成品状态。
type dnsBackend interface {
	// Kind 返回后端类型。
	Kind() dnsBackendKind
	// Apply 将指定网卡的 DNS 接管指向本机回环解析器 (127.0.0.1)。
	Apply(ctx context.Context, adapters []platform.AdapterInfo) error
	// Restore 依据接管前快照还原网卡 DNS 配置。
	Restore(ctx context.Context, adapters []platform.AdapterState) error
	// Flush 刷新系统 DNS 解析缓存。
	Flush(ctx context.Context) error
}

// detectBackend 按优先级自动探测当前系统可用的 DNS 后端：
// systemd-resolved → NetworkManager → 直接管理 /etc/resolv.conf。
//
// 探测仅依赖命令存在性与运行态，不修改任何系统配置。
func detectBackend(ctx context.Context, executor platform.CommandExecutor) dnsBackend {
	if isSystemdResolvedActive(ctx, executor) {
		return &resolvedBackend{executor: executor}
	}
	if isNetworkManagerActive(ctx, executor) {
		return &networkManagerBackend{executor: executor}
	}
	return &resolvConfBackend{executor: executor}
}

// commandExists 判断可执行文件是否存在于 PATH。
func commandExists(name string) bool {
	if strings.ContainsAny(name, "/") {
		if info, err := os.Stat(name); err == nil && !info.IsDir() {
			return true
		}
		return false
	}
	pathEnv := os.Getenv("PATH")
	for _, dir := range strings.Split(pathEnv, ":") {
		if dir == "" {
			continue
		}
		if info, err := os.Stat(dir + "/" + name); err == nil && !info.IsDir() {
			return true
		}
	}
	return false
}

// isSystemdResolvedActive 判断 systemd-resolved 是否正在托管系统解析。
func isSystemdResolvedActive(ctx context.Context, executor platform.CommandExecutor) bool {
	if !commandExists("resolvectl") {
		return false
	}
	out, err := runCommand(ctx, executor, "resolvectl", "status")
	if err != nil {
		return false
	}
	// resolvectl status 成功输出通常包含 "Global" 或 "Link" 段；
	// 若解析服务未运行则会报错或输出空内容。
	return strings.TrimSpace(out) != ""
}

// isNetworkManagerActive 判断 NetworkManager 是否正在运行并管理网络。
func isNetworkManagerActive(ctx context.Context, executor platform.CommandExecutor) bool {
	if !commandExists("nmcli") {
		return false
	}
	out, err := runCommand(ctx, executor, "nmcli", "-t", "-f", "RUNNING", "general")
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) == "running"
}

// interfaceNameFromAdapter 从适配器信息中提取可用于后端命令的接口名。
//
// Windows 使用 GUID 作为 ID；Linux 上 ID 与 Name 均为接口名（如 eth0）。
func interfaceNameFromAdapter(a platform.AdapterInfo) string {
	if a.ID != "" {
		return a.ID
	}
	return a.Name
}

// interfaceNameFromState 从适配器快照中提取接口名。
func interfaceNameFromState(a platform.AdapterState) string {
	if a.ID != "" {
		return a.ID
	}
	return a.Name
}

// isResidualLoopbackServer 判断 DNS 服务器地址是否指向本机回环。
func isResidualLoopbackServer(server string) bool {
	return platform.IsLoopbackOrLocalIP(server)
}
