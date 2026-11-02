package platform

import (
	"context"
	"os/exec"
	"strings"
)

// DefaultExecutor 生产环境使用的系统命令执行器。
//
// 实现完全平台无关：直接调用 PATH 中的可执行文件并返回合并输出。
type DefaultExecutor struct{}

// NewDefaultExecutor 创建默认命令执行器。
func NewDefaultExecutor() *DefaultExecutor {
	return &DefaultExecutor{}
}

// RunCommand 执行指定可执行文件并返回输出。
func (e *DefaultExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// IsDefaultExecutor 判断执行器是否为默认系统执行器（或未指定，指示处于生产运行环境）。
//
// 平台实现可借此区分"真实执行系统命令"与"测试注入的 Mock 执行器"。
func IsDefaultExecutor(e CommandExecutor) bool {
	if e == nil {
		return true
	}
	_, ok := e.(*DefaultExecutor)
	return ok
}
