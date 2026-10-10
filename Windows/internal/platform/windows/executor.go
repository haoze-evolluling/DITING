package windows

import (
	"context"
	"os/exec"
	"strings"
)

// CommandExecutor 定义系统命令执行接口，便于测试与多平台扩展
type CommandExecutor interface {
	RunCommand(ctx context.Context, name string, args ...string) (string, error)
}

// DefaultExecutor 生产环境使用的系统命令执行器
type DefaultExecutor struct{}

// NewDefaultExecutor 创建默认命令执行器
func NewDefaultExecutor() *DefaultExecutor {
	return &DefaultExecutor{}
}

// RunCommand 执行指定可执行文件并返回输出
func (e *DefaultExecutor) RunCommand(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// isDefaultExecutor 判断执行器是否为默认系统执行器（或未指定，指示处于生产运行环境）
func isDefaultExecutor(e CommandExecutor) bool {
	if e == nil {
		return true
	}
	_, ok := e.(*DefaultExecutor)
	return ok
}
