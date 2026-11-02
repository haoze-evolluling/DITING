//go:build linux

package linux

import (
	"context"
	"fmt"
	"os"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// DefaultPrivilegedExecutor Linux 平台的特权命令执行器。
//
// Linux 无 Windows UAC 等价的按需提权机制：进程一旦启动即固定其权限。
// 因此本实现直接以当前进程身份执行命令，并要求调用方已具备 root 权限
// （IsElevated 以 euid == 0 判定）。
type DefaultPrivilegedExecutor struct {
	executor platform.CommandExecutor
}

// NewDefaultPrivilegedExecutor 创建默认特权执行器。
func NewDefaultPrivilegedExecutor(executor platform.CommandExecutor) *DefaultPrivilegedExecutor {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	return &DefaultPrivilegedExecutor{executor: executor}
}

// IsElevated 报告当前进程是否以 root 身份运行。
func (e *DefaultPrivilegedExecutor) IsElevated() bool {
	return isRootUser()
}

// RunElevated 以当前身份执行命令。
//
// 由于无法在运行中提升权限，当进程非 root 时返回 ErrNotElevated，
// 提示用户使用 sudo 重新运行，而非静默失败。
func (e *DefaultPrivilegedExecutor) RunElevated(ctx context.Context, exe string, args ...string) error {
	if !e.IsElevated() {
		return ErrNotElevated
	}
	_, err := e.executor.RunCommand(ctx, exe, args...)
	return err
}

// ErrNotElevated 表示当前进程权限不足，需以 root 重新运行。
var ErrNotElevated = fmt.Errorf("当前权限不足，请以 root 身份重新运行（例如 sudo diting-service）")

// isRootUser 判断当前进程是否以 root 运行。
func isRootUser() bool {
	return os.Geteuid() == 0
}

// requireRoot 在特权操作入口返回明确的错误提示。
func requireRoot(op string) error {
	if !isRootUser() {
		return fmt.Errorf("%s 需要 root 权限，请使用 sudo 重试: %w", op, ErrNotElevated)
	}
	return nil
}
