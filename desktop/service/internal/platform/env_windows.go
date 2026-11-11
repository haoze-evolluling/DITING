//go:build windows

package platform

import "os"

// lookupEnv 读取环境变量。
func lookupEnv(key string) string {
	return os.Getenv(key)
}

// isRoot 在 Windows 平台上无意义，恒为 true（权限模型由 UAC 提权承担）。
func isRoot() bool {
	return true
}
