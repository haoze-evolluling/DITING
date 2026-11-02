//go:build windows

package windows

import (
	"fmt"
	"os"

	"github.com/haoze-evolluling/diting/server/internal/platform"
	"golang.org/x/sys/windows/registry"
)

const (
	runRegistryKey = `Software\Microsoft\Windows\CurrentVersion\Run`
	runValueName   = "DitingDNS"
)

// WindowsAutoStartManager 负责通过 Windows 注册表管理当前用户的开机自启配置。
type WindowsAutoStartManager struct{}

// NewAutoStartManager 构造 Windows 自启管理器。
func NewAutoStartManager() platform.AutoStartManager {
	return &WindowsAutoStartManager{}
}

// IsEnabled 检查当前用户是否已启用开机自启。
//
// 仅针对当前用户：桌面端开关的语义就是"本用户的登录自启"，
// 跨用户的托管情况由服务状态查询另行汇总。
func (m *WindowsAutoStartManager) IsEnabled() bool {
	return runValuePresent(registry.CURRENT_USER)
}

// loginItemEnabled 检查任一用户会话的登录启动项中是否存在谛听条目。
//
// 除当前进程用户外，还扫描 HKEY_USERS 下所有已加载的用户配置单元，
// 以覆盖"服务以 LocalSystem 身份运行、而自启项登记在交互用户下"的场景。
func loginItemEnabled() bool {
	if runValuePresent(registry.CURRENT_USER) {
		return true
	}

	names, err := registry.USERS.ReadSubKeyNames(0)
	if err != nil {
		return false
	}
	for _, sid := range names {
		if runValuePresent(registry.USERS, sid) {
			return true
		}
	}
	return false
}

// runValuePresent 判断指定用户配置单元下的 Run 键是否登记了谛听启动项。
func runValuePresent(root registry.Key, subKeys ...string) bool {
	path := runRegistryKey
	for _, sub := range subKeys {
		path = sub + `\` + path
	}
	k, err := registry.OpenKey(root, path, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()
	_, _, err = k.GetStringValue(runValueName)
	return err == nil
}

// SetEnabled 开启或关闭当前用户的开机自启。
func (m *WindowsAutoStartManager) SetEnabled(enable bool) (bool, error) {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, runRegistryKey, registry.SET_VALUE)
	if err != nil {
		return false, fmt.Errorf("访问注册表失败: %w", err)
	}
	defer k.Close()

	if enable {
		exePath, err := os.Executable()
		if err != nil {
			return false, fmt.Errorf("获取执行路径失败: %w", err)
		}
		if err := k.SetStringValue(runValueName, `"`+exePath+`" --minimized`); err != nil {
			return false, fmt.Errorf("写入自启注册表失败: %w", err)
		}
		return true, nil
	}

	_ = k.DeleteValue(runValueName)
	return false, nil
}
