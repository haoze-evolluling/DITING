package windows

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// CommandExecutor 定义系统命令执行接口，便于测试与多平台扩展
type CommandExecutor interface {
	RunCommand(ctx context.Context, name string, args ...string) (string, error)
	RunPowerShell(ctx context.Context, script string) (string, error)
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

// RunPowerShell 执行 PowerShell 脚本，显式设置 UTF-8 输出编码以避免中文乱码。
// 分离 stdout 与 stderr，防止底层非致命警告或错误流混入标准输出导致 JSON 反序列化失败。
func (e *DefaultExecutor) RunPowerShell(ctx context.Context, script string) (string, error) {
	wrapped := "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; " + script
	cmd := exec.CommandContext(ctx, "powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", wrapped)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		errStr := strings.TrimSpace(stderr.String())
		if errStr == "" {
			errStr = strings.TrimSpace(stdout.String())
		}
		return strings.TrimSpace(stdout.String()), fmt.Errorf("%w: %s", err, errStr)
	}
	return strings.TrimSpace(stdout.String()), nil
}

