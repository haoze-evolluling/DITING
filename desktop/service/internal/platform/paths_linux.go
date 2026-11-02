//go:build linux

package platform

import "path/filepath"

// Linux 平台遵循 FHS：
//   - 配置（管理员维护、需持久化）→ /etc/diting
//   - 状态（运行时快照、缓存）    → /var/lib/diting
const (
	linuxConfigDir = "/etc/diting"
	linuxStateDir  = "/var/lib/diting"
)

// defaultDataDir 返回 Linux 平台的数据根目录。
//
// 非 root 运行（如 WSL 调试）时自动退避至 ~/.diting，
// 避免因无写权限导致服务启动失败。
func defaultDataDir() string {
	if isRoot() {
		return linuxStateDir
	}
	if home := lookupEnv("HOME"); home != "" {
		return filepath.Join(home, ".diting")
	}
	return linuxStateDir
}

// defaultConfigDir 返回 Linux 平台的配置目录。
func defaultConfigDir() string {
	if isRoot() {
		return linuxConfigDir
	}
	if home := lookupEnv("HOME"); home != "" {
		return filepath.Join(home, ".diting")
	}
	return linuxConfigDir
}
