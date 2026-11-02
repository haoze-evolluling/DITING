//go:build linux

package linux

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// resolvConfBackend 直接管理 /etc/resolv.conf 静态文件。
//
// 适用于未运行 systemd-resolved 与 NetworkManager 的极简发行版
// （容器、Alpine、部分服务器环境）。接管时将 nameserver 全量替换为
// 本机回环地址；还原时按接管前保存的原始文件内容写回。
//
// 该后端在写入前会保存 /etc/resolv.conf 原始内容到数据目录备份中，
// 并额外生成离线恢复脚本 restore-dns.sh，确保服务异常时仍可手动恢复。
type resolvConfBackend struct {
	executor platform.CommandExecutor
}

// Kind 返回后端类型。
func (b *resolvConfBackend) Kind() dnsBackendKind { return backendResolvConf }

// Apply 将 /etc/resolv.conf 重写为本机回环解析器。
func (b *resolvConfBackend) Apply(ctx context.Context, adapters []platform.AdapterInfo) error {
	if content, err := readResolvConf(); err == nil {
		if err := writeBackupContent("resolv.conf", content); err != nil {
			return fmt.Errorf("备份 resolv.conf 失败: %w", err)
		}
		// 离线恢复脚本读取的是 /etc/resolv.conf.diting.orig，必须与接管同时落盘，
		// 否则该脚本的首选还原分支永远不存在（BUG-17）。
		if err := writeResolvConfOriginal(content); err != nil {
			return fmt.Errorf("备份 /etc/resolv.conf.diting.orig 失败: %w", err)
		}
	} else {
		_ = os.Remove(resolvConfOriginalPath)
	}

	if err := writeResolvConfAtomically(renderResolvConf([]string{"127.0.0.1", "::1"})); err != nil {
		return err
	}
	return b.Flush(ctx)
}

// Restore 从备份还原 /etc/resolv.conf。
func (b *resolvConfBackend) Restore(ctx context.Context, adapters []platform.AdapterState) error {
	content, err := readBackupContent("resolv.conf")
	if err != nil {
		// 无可用备份时回退为公共解析器，保证基本连通性
		content = renderResolvConf([]string{"223.5.5.5", "119.29.29.29"})
	}
	if err := writeResolvConfAtomically(content); err != nil {
		return err
	}
	// 还原成功后原始备份不再有用，留着会被下次接管误当成「更早的原配置」
	_ = os.Remove(resolvConfOriginalPath)
	return b.Flush(ctx)
}

// Flush 在无托管服务时通常无缓存可刷，保留接口一致性。
func (b *resolvConfBackend) Flush(ctx context.Context) error {
	if commandExists("resolvectl") {
		_, err := runCommand(ctx, b.executor, "resolvectl", "flush-caches")
		return err
	}
	return nil
}

// resolvConfOriginalPath 是离线恢复脚本 restore-dns.sh 读取的接管前原始文件。
const resolvConfOriginalPath = "/etc/resolv.conf.diting.orig"

// writeResolvConfOriginal 将接管前的 resolv.conf 原文写到脚本约定的路径。
func writeResolvConfOriginal(content string) error {
	return os.WriteFile(resolvConfOriginalPath, []byte(content), 0o600)
}

// writeBackupContent 将文本内容备份至数据目录。
func writeBackupContent(name, content string) error {
	path := backupPathFor(name)
	if err := ensureParentDir(path); err != nil {
		return err
	}
	return writeFileMode(path, []byte(content), 0o600)
}

// readBackupContent 读取数据目录中的备份内容。
func readBackupContent(name string) (string, error) {
	data, err := readFileAt(backupPathFor(name))
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// currentSystemServers 返回当前系统实际使用的解析服务器列表（用于诊断展示）。
func currentSystemServers() []string {
	content, err := readResolvConf()
	if err != nil {
		return nil
	}
	var out []string
	for _, s := range parseResolvConf(content) {
		if strings.TrimSpace(s) != "" {
			out = append(out, s)
		}
	}
	return out
}
