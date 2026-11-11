package platform

import (
	"errors"
	"runtime"
)

// ErrUnsupported 表示当前平台不支持所请求的能力。
var ErrUnsupported = errors.New("当前平台不支持该操作")

// Unsupported 构造一个带操作说明的不支持错误。
//
// 上层可据此优雅降级（例如在缺少防火墙管理器的 Linux 环境中
// 跳过放行步骤并给出诊断提示），而不是让启动流程直接失败。
func Unsupported(op string) error {
	return errUnsupported(op)
}

func errUnsupported(op string) error {
	return &unsupportedError{op: op}
}

type unsupportedError struct {
	op string
}

func (e *unsupportedError) Error() string {
	if e.op == "" {
		return ErrUnsupported.Error()
	}
	return "当前平台 (" + runtime.GOOS + ") 不支持该操作: " + e.op
}

func (e *unsupportedError) Is(target error) bool {
	return target == ErrUnsupported
}

func (e *unsupportedError) Unwrap() error {
	return ErrUnsupported
}
