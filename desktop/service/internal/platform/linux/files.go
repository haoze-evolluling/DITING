//go:build linux

package linux

import (
	"errors"
	"os"
	"path/filepath"
)

// ensureParentDir 确保文件所在目录存在，并以 0700 权限创建。
func ensureParentDir(path string) error {
	return os.MkdirAll(filepath.Dir(path), 0o700)
}

// writeFileMode 确保父目录存在后按指定权限写入文件。
func writeFileMode(path string, data []byte, perm os.FileMode) error {
	if err := ensureParentDir(path); err != nil {
		return err
	}
	return os.WriteFile(path, data, perm)
}

// readFileAt 读取指定路径的完整内容。
func readFileAt(path string) ([]byte, error) {
	return os.ReadFile(path)
}

// fileExists 判断路径是否为存在的普通文件。
func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// removePath 删除文件，语义同 os.Remove。
func removePath(path string) error {
	return os.Remove(path)
}

// isNotExist 判断错误是否为"文件不存在"。
func isNotExist(err error) bool {
	return errors.Is(err, os.ErrNotExist)
}
