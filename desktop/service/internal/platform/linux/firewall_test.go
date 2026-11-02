//go:build linux

package linux

import (
	"os"
	"path/filepath"
	"testing"
)

// TestFirewallBackendNameNone 验证在 PATH 中不存在任何防火墙管理器时，
// 后端探测结果为 "none"——这正是 WSL/极简容器环境的情形，UI 应据此
// 呈现"无需放行"而非报错。
func TestFirewallBackendNameNone(t *testing.T) {
	t.Setenv("PATH", "")

	if got := FirewallBackendName(); got != "none" {
		t.Errorf("无任何防火墙管理器时 FirewallBackendName() = %q, 期望 %q", got, "none")
	}
}

// TestFirewallBackendNameDetectsUfw 验证探测到 ufw 时返回对应后端名，
// 保证"有防火墙"与"无防火墙"两条路径可被区分。
func TestFirewallBackendNameDetectsUfw(t *testing.T) {
	dir := t.TempDir()
	fake := filepath.Join(dir, "ufw")
	if err := os.WriteFile(fake, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatalf("写入假 ufw 失败: %v", err)
	}
	t.Setenv("PATH", dir)

	if got := FirewallBackendName(); got != "ufw" {
		t.Errorf("探测到 ufw 时 FirewallBackendName() = %q, 期望 %q", got, "ufw")
	}
}

// TestFirewallBackendNamePriority 验证探测优先级 firewalld → ufw → nftables → iptables。
func TestFirewallBackendNamePriority(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"firewall-cmd", "ufw", "nft", "iptables"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatalf("写入假 %s 失败: %v", name, err)
		}
	}
	t.Setenv("PATH", dir)

	if got := FirewallBackendName(); got != "firewalld" {
		t.Errorf("全部存在时应优先 firewalld, got=%q", got)
	}
}
