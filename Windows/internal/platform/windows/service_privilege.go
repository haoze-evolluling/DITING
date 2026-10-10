package windows

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"golang.org/x/sys/windows"
)

const (
	// DefaultServiceName 谛听后台核心服务名称
	DefaultServiceName = "DitingDNSService"
	// DefaultServiceDisplayName 谛听后台核心服务显示名称
	DefaultServiceDisplayName = "谛听 DNS 内核特权服务"
)

var (
	// ErrUACCancelled 用户取消管理员权限授权
	ErrUACCancelled = errors.New("用户取消了管理员权限授权")
	// ErrServiceExeNotFound 未找到核心服务执行程序
	ErrServiceExeNotFound = errors.New("未找到后台核心服务执行程序 (diting-service.exe)")

	modShell32          = windows.NewLazySystemDLL("shell32.dll")
	procShellExecuteExW = modShell32.NewProc("ShellExecuteExW")
)

const (
	seeMaskNoCloseProcess = 0x00000040
	swHide                = 0
)

type shellExecuteInfo struct {
	cbSize       uint32
	fMask        uint32
	hwnd         windows.Handle
	lpVerb       *uint16
	lpFile       *uint16
	lpParameters *uint16
	lpDirectory  *uint16
	nShow        int32
	hInstApp     windows.Handle
	lpIDList     uintptr
	lpClass      *uint16
	hkeyClass    windows.Handle
	dwHotKey     uint32
	hIcon        windows.Handle
	hProcess     windows.Handle
}

// CoreServiceStatus 核心服务状态
type CoreServiceStatus struct {
	Installed      bool   `json:"installed"`
	Running        bool   `json:"running"`
	State          string `json:"state"` // running, stopped, not_installed, start_pending, stop_pending, unknown
	StateText      string `json:"stateText"`
	ExecutablePath string `json:"executablePath"`
	IsElevated     bool   `json:"isElevated"`
	CanInstall     bool   `json:"canInstall"`
	Message        string `json:"message"`
}

// PrivilegedExecutor 特权命令执行接口，支持测试 Mock
type PrivilegedExecutor interface {
	RunElevated(ctx context.Context, exe string, args ...string) error
	IsElevated() bool
}

// DefaultPrivilegedExecutor 默认特权命令执行器（基于 Win32 原生 API）
type DefaultPrivilegedExecutor struct {
	executor CommandExecutor
}

// NewDefaultPrivilegedExecutor 创建默认特权执行器
func NewDefaultPrivilegedExecutor(executor CommandExecutor) *DefaultPrivilegedExecutor {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	return &DefaultPrivilegedExecutor{executor: executor}
}

// IsRunningAsAdmin 检查当前进程是否具有管理员令牌
func IsRunningAsAdmin() bool {
	var sid *windows.SID
	err := windows.AllocateAndInitializeSid(
		&windows.SECURITY_NT_AUTHORITY,
		2,
		windows.SECURITY_BUILTIN_DOMAIN_RID,
		windows.DOMAIN_ALIAS_RID_ADMINS,
		0, 0, 0, 0, 0, 0,
		&sid,
	)
	if err != nil {
		return false
	}
	defer windows.FreeSid(sid)

	token := windows.GetCurrentProcessToken()
	member, err := token.IsMember(sid)
	if err != nil {
		return false
	}
	return member
}

func (e *DefaultPrivilegedExecutor) IsElevated() bool {
	return IsRunningAsAdmin()
}

// RunElevated 请求管理员权限执行程序（底层使用 Win32 ShellExecuteEx 原生 API）
func (e *DefaultPrivilegedExecutor) RunElevated(ctx context.Context, exe string, args ...string) error {
	if e.IsElevated() {
		cmd := exec.CommandContext(ctx, exe, args...)
		out, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("特权操作执行失败: %w (输出: %s)", err, strings.TrimSpace(string(out)))
		}
		return nil
	}
	return runElevatedNative(ctx, exe, windows.ComposeCommandLine(args))
}
