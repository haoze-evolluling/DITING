//go:build linux

package platform

import "os"

// lookupEnv 读取环境变量。
func lookupEnv(key string) string {
	return os.Getenv(key)
}

// isRoot 报告当前进程是否以 root 身份运行。
func isRoot() bool {
	return os.Geteuid() == 0
}
