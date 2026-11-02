//go:build linux

package linux

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// LinuxAutoStartManager 通过 XDG autostart 规范管理 Linux 桌面的自启配置。
type LinuxAutoStartManager struct{}

// NewAutoStartManager 构造 Linux 自启管理器。
func NewAutoStartManager() platform.AutoStartManager {
	return &LinuxAutoStartManager{}
}

func (m *LinuxAutoStartManager) desktopFilePath() string {
	return desktopFilePath()
}

// desktopFilePath 返回 XDG 桌面自启条目的绝对路径（无法定位时为 ""）。
func desktopFilePath() string {
	configDir := os.Getenv("XDG_CONFIG_HOME")
	if configDir == "" {
		home := os.Getenv("HOME")
		if home == "" {
			return ""
		}
		configDir = filepath.Join(home, ".config")
	}
	return filepath.Join(configDir, "autostart", "diting.desktop")
}

// xdgAutoStartPresent 判断 XDG 桌面自启条目是否已存在。
//
// 供服务状态查询复用：当核心服务由桌面应用而非 systemd 托管时，
// 该条目才是开机自启的实际生效依据。
func xdgAutoStartPresent() bool {
	p := desktopFilePath()
	if p == "" {
		return false
	}
	data, err := os.ReadFile(p)
	if err != nil {
		return false
	}
	// 只判断文件存在会把「Exec 指向已不存在的二进制」也报成已启用；
	// 能解析出路径时按可执行文件是否存在判定，解析不了才退回存在性。
	if exe := parseDesktopExec(string(data)); exe != "" {
		info, statErr := os.Stat(exe)
		return statErr == nil && !info.IsDir()
	}
	return true
}

// parseDesktopExec 从桌面条目的 Exec 行提取可执行文件路径（支持引号与反斜杠转义）。
func parseDesktopExec(content string) string {
	for _, line := range strings.Split(content, "\n") {
		if !strings.HasPrefix(line, "Exec=") {
			continue
		}
		value := strings.TrimSpace(strings.TrimPrefix(line, "Exec="))
		if value == "" {
			return ""
		}
		if value[0] == '"' {
			var b strings.Builder
			escaped := false
			for i := 1; i < len(value); i++ {
				c := value[i]
				if escaped {
					b.WriteByte(c)
					escaped = false
					continue
				}
				if c == '\\' {
					escaped = true
					continue
				}
				if c == '"' {
					return b.String()
				}
				b.WriteByte(c)
			}
			return b.String()
		}
		return strings.Fields(value)[0]
	}
	return ""
}

// IsEnabled 检查 Linux 桌面自启条目是否存在。
func (m *LinuxAutoStartManager) IsEnabled() bool {
	return xdgAutoStartPresent()
}

// execValue 按 Desktop Entry 规范（GShell / GSEsc）转义 Exec 的可执行路径。
//
// 路径里的空格是 argv 分隔符、`%` 是字段码占位符、反斜杠/引号/反引号/美元
// 有 shell 语义，都需要转义或加引号，否则自启条目会静默启动失败。
func execValue(path string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range path {
		switch r {
		case '\\', '"', '`', '$':
			b.WriteByte('\\')
			b.WriteRune(r)
		case '%':
			b.WriteString("%%")
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// SetEnabled 创建或移除 ~/.config/autostart/diting.desktop。
func (m *LinuxAutoStartManager) SetEnabled(enable bool) (bool, error) {
	p := m.desktopFilePath()
	if p == "" {
		return false, fmt.Errorf("无法获取用户配置目录 (HOME/XDG_CONFIG_HOME 未设置)")
	}

	if enable {
		exePath, err := os.Executable()
		if err != nil {
			return false, fmt.Errorf("获取执行路径失败: %w", err)
		}
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return false, fmt.Errorf("创建自启目录失败: %w", err)
		}
		entry := fmt.Sprintf("[Desktop Entry]\nType=Application\nName=谛听 DNS\nExec=%s\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\n", execValue(exePath))
		if err := os.WriteFile(p, []byte(entry), 0o644); err != nil {
			return false, fmt.Errorf("写入自启桌面条目失败: %w", err)
		}
		return true, nil
	}

	if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
		return false, fmt.Errorf("移除自启桌面条目失败: %w", err)
	}
	return false, nil
}
