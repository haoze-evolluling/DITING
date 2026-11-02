//go:build linux

package linux

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// GenerateRestoreScript 生成独立离线恢复脚本 restore-dns.sh。
//
// 该脚本不依赖本程序，用于服务无法启动时手动还原系统 DNS 配置。
// 脚本内容按当前探测到的后端裁剪，仅包含对应后端可用的还原路径，
// 并会在执行前保存一份当前 /etc/resolv.conf 快照以便二次回退。
func GenerateRestoreScript(kind dnsBackendKind, adapters []platform.AdapterState, outputPath string) error {
	var sb strings.Builder
	sb.WriteString("#!/bin/sh\n")
	sb.WriteString("# ================================================================\n")
	sb.WriteString("#   谛听 (DITING) 紧急离线 DNS 还原脚本\n")
	sb.WriteString(fmt.Sprintf("#   生成时间: %s\n", time.Now().Format("2006-01-02 15:04:05")))
	sb.WriteString(fmt.Sprintf("#   接管后端: %s\n", kind.String()))
	sb.WriteString("# ================================================================\n\n")
	sb.WriteString("set -u\n\n")
	sb.WriteString("if [ \"$(id -u)\" != \"0\" ]; then\n")
	sb.WriteString("    echo \"[错误] 请以 root 身份运行：sudo sh $0\" >&2\n")
	sb.WriteString("    exit 1\n")
	sb.WriteString("fi\n\n")
	sb.WriteString("echo \"[1/3] 备份当前 /etc/resolv.conf ...\"\n")
	sb.WriteString("cp -a /etc/resolv.conf /etc/resolv.conf.diting.bak 2>/dev/null || true\n\n")
	sb.WriteString("echo \"[2/3] 还原网卡 DNS 配置 ...\"\n")

	switch kind {
	case backendSystemdResolved:
		writeResolvedRestore(&sb, adapters)
	case backendNetworkManager:
		writeNetworkManagerRestore(&sb, adapters)
	default:
		writeResolvConfRestore(&sb, adapters)
	}

	sb.WriteString("\necho \"[3/3] 刷新系统 DNS 解析缓存 ...\"\n")
	sb.WriteString("command -v resolvectl >/dev/null 2>&1 && resolvectl flush-caches || true\n")
	sb.WriteString("command -v systemd-resolve >/dev/null 2>&1 && systemd-resolve --flush-caches || true\n\n")
	sb.WriteString("echo \"============================================================\"\n")
	sb.WriteString("echo \"系统 DNS 设置已还原。若解析仍异常，可手动编辑 /etc/resolv.conf\"\n")
	sb.WriteString("echo \"或执行 'wsl --shutdown'（WSL 环境）后重新进入以重置网络。\"\n")
	sb.WriteString("echo \"============================================================\"\n")

	dir := filepath.Dir(outputPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	return os.WriteFile(outputPath, []byte(sb.String()), 0o755)
}

// writeResolvedRestore 追加 systemd-resolved 的还原指令。
func writeResolvedRestore(sb *strings.Builder, adapters []platform.AdapterState) {
	for _, raw := range adapters {
		a := platform.CleanAdapterState(raw)
		iface := interfaceNameFromState(a)
		if iface == "" {
			continue
		}

		servers := mergeDualStackServers(a)
		sb.WriteString(fmt.Sprintf("echo \"  还原网卡 [%s] ...\"\n", iface))
		if len(servers) == 0 {
			sb.WriteString(fmt.Sprintf("resolvectl revert %s 2>/dev/null || true\n", iface))
			continue
		}
		sb.WriteString(fmt.Sprintf("resolvectl dns %s %s 2>/dev/null || true\n", iface, strings.Join(servers, " ")))
		sb.WriteString(fmt.Sprintf("resolvectl domain %s '~.' 2>/dev/null || true\n", iface))
	}
}

// writeNetworkManagerRestore 追加 NetworkManager 的还原指令。
func writeNetworkManagerRestore(sb *strings.Builder, adapters []platform.AdapterState) {
	for _, raw := range adapters {
		a := platform.CleanAdapterState(raw)
		name := interfaceNameFromState(a)
		if name == "" {
			continue
		}

		v4 := strings.Join(a.IPv4DNS, ",")
		v6 := strings.Join(a.IPv6DNS, ",")
		sb.WriteString(fmt.Sprintf("echo \"  还原连接 [%s] ...\"\n", name))
		sb.WriteString(fmt.Sprintf("nmcli con mod %q ipv4.dns %q ipv6.dns %q \\\n", name, v4, v6))
		sb.WriteString("    ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no 2>/dev/null || true\n")
		sb.WriteString(fmt.Sprintf("nmcli con up %q 2>/dev/null || true\n", name))
	}
}

// writeResolvConfRestore 追加 /etc/resolv.conf 的还原指令。
func writeResolvConfRestore(sb *strings.Builder, adapters []platform.AdapterState) {
	servers := collectSnapshotServers(adapters)
	sb.WriteString("if [ -f /etc/resolv.conf.diting.orig ]; then\n")
	sb.WriteString("    echo \"  从接管前备份还原 /etc/resolv.conf ...\"\n")
	sb.WriteString("    cat /etc/resolv.conf.diting.orig > /etc/resolv.conf\n")
	sb.WriteString("else\n")
	sb.WriteString("    echo \"  写入接管前记录的解析服务器 ...\"\n")
	sb.WriteString("    {\n")
	sb.WriteString("        echo '# Restored by DITING.'\n")
	if len(servers) == 0 {
		sb.WriteString("        echo 'nameserver 223.5.5.5'\n")
		sb.WriteString("        echo 'nameserver 119.29.29.29'\n")
	}
	for _, s := range servers {
		sb.WriteString(fmt.Sprintf("        echo 'nameserver %s'\n", s))
	}
	sb.WriteString("    } > /etc/resolv.conf\n")
	sb.WriteString("fi\n")
}

// collectSnapshotServers 汇总所有快照中的 DNS 服务器（去重，供 resolv.conf 还原使用）。
func collectSnapshotServers(adapters []platform.AdapterState) []string {
	seen := make(map[string]bool)
	var out []string
	for _, raw := range adapters {
		for _, s := range mergeDualStackServers(platform.CleanAdapterState(raw)) {
			if seen[s] {
				continue
			}
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
