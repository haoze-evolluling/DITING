//go:build linux

package linux

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// LinuxServiceManager 基于 kardianos/service (systemd) 的后台服务生命周期管理器。
//
// 与 Windows 版语义对应：状态查询、启停重启、安装卸载，区别在于
// Linux 无按需提权弹窗，全部操作要求当前进程已具备 root 权限。
type LinuxServiceManager struct {
	serviceName string
	unitName    string
	executor    platform.CommandExecutor
	privExec    platform.PrivilegedExecutor
	locateExe   func() (string, error)
}

// NewServiceManager 创建服务管理器。
func NewServiceManager(executor platform.CommandExecutor, privExec platform.PrivilegedExecutor) *LinuxServiceManager {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	if privExec == nil {
		privExec = NewDefaultPrivilegedExecutor(executor)
	}
	m := &LinuxServiceManager{
		serviceName: DefaultServiceName,
		unitName:    DefaultServiceName + ".service",
		executor:    executor,
		privExec:    privExec,
	}
	m.locateExe = m.LocateExecutable
	return m
}

const (
	// DefaultServiceName 后台核心服务名（systemd 单元名 diting-dnsservice.service）。
	DefaultServiceName = "diting-dnsservice"
	// DefaultServiceDisplayName 后台核心服务显示名。
	DefaultServiceDisplayName = "谛听 DNS 内核特权服务"
)

// locate 定位服务可执行文件（locateExe 便于测试注入）。
func (m *LinuxServiceManager) locate() (string, error) {
	if m.locateExe != nil {
		return m.locateExe()
	}
	return m.LocateExecutable()
}

// LocateExecutable 查找 diting-service 可执行文件位置。
//
// 依次尝试：systemd 单元 ExecStart 中记录的路径 → 常见安装路径 →
// 与当前进程同级目录 → 构建产物目录 → PATH。
func (m *LinuxServiceManager) LocateExecutable() (string, error) {
	if path, err := m.executableFromUnit(context.Background()); err == nil && path != "" {
		if fileExists(path) {
			return path, nil
		}
	}

	candidates := []string{
		"/usr/local/bin/diting-service",
		"/usr/bin/diting-service",
		"/opt/diting/diting-service",
		"./build/bin/diting-service",
		"build/bin/diting-service",
	}
	for _, c := range candidates {
		if fileExists(c) {
			// systemd 以 / 为工作目录解析 ExecStart，相对路径写进单元必然失败，
			// 这里统一归一为绝对路径。
			return absExecutablePath(c), nil
		}
	}

	for _, name := range []string{"diting-service"} {
		if commandExists(name) {
			if resolved, err := exec.LookPath(name); err == nil {
				return absExecutablePath(resolved), nil
			}
			return absExecutablePath(name), nil
		}
	}

	return "", errors.New("未找到 diting-service 可执行文件")
}

// absExecutablePath 将可执行路径归一为绝对路径，失败时原样返回。
func absExecutablePath(path string) string {
	if path == "" || filepath.IsAbs(path) {
		return path
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

// executableFromUnit 从 systemctl show 的 ExecStart 字段解析可执行文件路径。
func (m *LinuxServiceManager) executableFromUnit(ctx context.Context) (string, error) {
	out, err := runCommand(ctx, m.executor, "systemctl", "show", m.unitName, "-p", "ExecStart", "--value")
	if err != nil {
		return "", err
	}
	path := parseExecStartPath(out)
	if path == "" {
		return "", fmt.Errorf("单元 %s 未配置 ExecStart", m.unitName)
	}
	return path, nil
}

// parseExecStartPath 从 ExecStart 行中提取可执行文件路径。
//
// 形如：{ path=/usr/local/bin/diting-service ; argv[]=/usr/local/bin/diting-service -run ; ... }
func parseExecStartPath(out string) string {
	trimmed := strings.TrimSpace(out)
	if trimmed == "" || trimmed == "unknown" {
		return ""
	}
	if idx := strings.Index(trimmed, "path="); idx >= 0 {
		rest := trimmed[idx+len("path="):]
		if end := strings.Index(rest, " "); end >= 0 {
			rest = rest[:end]
		}
		return strings.Trim(rest, ";")
	}
	// 非结构化输出：取第一个字段
	fields := strings.Fields(trimmed)
	if len(fields) > 0 {
		return fields[0]
	}
	return ""
}

// serviceStatus 描述 systemd 单元的解析结果。
type serviceStatus struct {
	loadState     string
	activeState   string
	subState      string
	unitFileState string
}

// GetStatus 获取当前核心服务状态。
func (m *LinuxServiceManager) GetStatus(ctx context.Context) (*platform.CoreServiceStatus, error) {
	status := &platform.CoreServiceStatus{
		State:      "unknown",
		StateText:  "未知状态",
		IsElevated: m.privExec.IsElevated(),
	}

	if exePath, err := m.locate(); err == nil {
		status.ExecutablePath = exePath
		status.CanInstall = true
	} else {
		status.CanInstall = false
	}

	raw, err := runCommand(ctx, m.executor, "systemctl", "show", m.unitName,
		"-p", "LoadState,ActiveState,SubState,UnitFileState")
	if err != nil {
		return status, fmt.Errorf("检测核心服务状态失败: %w", err)
	}

	parsed := parseSystemctlShow(raw)
	applyServiceStatus(status, parsed)
	status.AutoStart = m.autoStartStatus(parsed)
	return status, nil
}

// autoStartStatus 汇总 Linux 宿主机上所有已生效的开机自启托管机制。
func (m *LinuxServiceManager) autoStartStatus(st serviceStatus) *platform.AutoStartStatus {
	if st.unitFileState == "enabled" {
		return &platform.AutoStartStatus{
			Enabled:   true,
			Mechanism: platform.AutoStartMechanismSystemd,
			Detail:    "systemd 单元已 enable，开机无需登录即可守护运行。",
		}
	}
	if st.unitFileState == "masked" || st.unitFileState == "disabled" {
		return &platform.AutoStartStatus{
			Enabled:   false,
			Mechanism: platform.AutoStartMechanismNone,
			Detail:    "systemd 单元已被 disable/mask，开机不会自动运行。",
		}
	}

	// 非 systemd 托管的发行版或单元未安装时，回退检查桌面登录自启条目。
	if xdgAutoStartPresent() {
		return &platform.AutoStartStatus{
			Enabled:   true,
			Mechanism: platform.AutoStartMechanismXDG,
			Detail:    "已加入 XDG 桌面登录自启条目，登录桌面后自动运行。",
		}
	}
	return &platform.AutoStartStatus{
		Enabled:   false,
		Mechanism: platform.AutoStartMechanismNone,
		Detail:    "尚未配置任何开机自启托管机制。",
	}
}

// parseSystemctlShow 解析 systemctl show 的 Key=Value 输出。
func parseSystemctlShow(out string) serviceStatus {
	var st serviceStatus
	for _, line := range strings.Split(out, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch key {
		case "LoadState":
			st.loadState = value
		case "ActiveState":
			st.activeState = value
		case "SubState":
			st.subState = value
		case "UnitFileState":
			st.unitFileState = value
		}
	}
	return st
}

// applyServiceStatus 将 systemd 状态映射为跨平台的 CoreServiceStatus。
func applyServiceStatus(status *platform.CoreServiceStatus, st serviceStatus) {
	if st.loadState == "not-found" || st.loadState == "" {
		status.Installed = false
		status.Running = false
		status.State = "not_installed"
		status.StateText = "未安装"
		status.Message = "后台核心服务尚未安装到系统中。"
		return
	}

	status.Installed = true
	status.Running = st.activeState == "active"

	switch st.activeState {
	case "active":
		status.State = "running"
		status.StateText = "运行中"
		status.Message = "核心服务正常运行中。"
	case "activating":
		status.State = "start_pending"
		status.StateText = "正在启动"
		status.Message = "核心服务正在启动中..."
	case "deactivating":
		status.State = "stop_pending"
		status.StateText = "正在停止"
		status.Message = "核心服务正在停止中..."
	case "failed":
		status.State = "stopped"
		status.StateText = "已停止"
		status.Message = "核心服务运行失败，请执行 journalctl -u " + DefaultServiceName + " 查看日志。"
	default:
		status.State = "stopped"
		status.StateText = "已停止"
		status.Message = "核心服务已安装，当前处于停止状态。"
	}
}

// StartService 启动核心服务（要求 root）。
func (m *LinuxServiceManager) StartService(ctx context.Context) error {
	return m.control(ctx, "start")
}

// StopService 停止核心服务（要求 root）。
func (m *LinuxServiceManager) StopService(ctx context.Context) error {
	return m.control(ctx, "stop")
}

// RestartService 重启核心服务（要求 root）。
func (m *LinuxServiceManager) RestartService(ctx context.Context) error {
	return m.control(ctx, "restart")
}

// control 以 root 身份执行 systemctl 控制命令。
func (m *LinuxServiceManager) control(ctx context.Context, action string) error {
	if err := requireRoot("服务控制"); err != nil {
		return err
	}
	if _, err := runCommand(ctx, m.executor, "systemctl", action, m.serviceName); err != nil {
		return fmt.Errorf("服务控制操作 [%s] 失败: %w", action, err)
	}
	return nil
}

// InstallService 安装核心服务单元并启用开机自启（要求 root）。
func (m *LinuxServiceManager) InstallService(ctx context.Context, exePath string) error {
	if err := requireRoot("安装服务"); err != nil {
		return err
	}
	if exePath == "" {
		p, err := m.locate()
		if err != nil {
			return err
		}
		exePath = p
	}

	unit := renderSystemdUnit(absExecutablePath(exePath))
	if err := writeFileMode("/etc/systemd/system/"+m.unitName, []byte(unit), 0o644); err != nil {
		return fmt.Errorf("写入 systemd 单元失败: %w", err)
	}
	if _, err := runCommand(ctx, m.executor, "systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("重载 systemd 配置失败: %w", err)
	}
	if _, err := runCommand(ctx, m.executor, "systemctl", "enable", m.serviceName); err != nil {
		return fmt.Errorf("设置开机自启失败: %w", err)
	}
	return nil
}

// InstallAndStartService 安装并立即启动核心服务。
func (m *LinuxServiceManager) InstallAndStartService(ctx context.Context, exePath string) error {
	if err := m.InstallService(ctx, exePath); err != nil {
		// 已安装时继续尝试启动
		_ = err
	}
	return m.StartService(ctx)
}

// UninstallService 停止、禁用并卸载核心服务（要求 root）。
func (m *LinuxServiceManager) UninstallService(ctx context.Context) error {
	if err := requireRoot("卸载服务"); err != nil {
		return err
	}
	_, _ = runCommand(ctx, m.executor, "systemctl", "stop", m.serviceName)
	_, _ = runCommand(ctx, m.executor, "systemctl", "disable", m.serviceName)

	if err := removeFile(unitFilePath(m.unitName)); err != nil {
		return fmt.Errorf("删除 systemd 单元失败: %w", err)
	}
	_, _ = runCommand(ctx, m.executor, "systemctl", "daemon-reload")
	return nil
}

// unitFilePath 返回 systemd 单元文件路径。
func unitFilePath(unitName string) string {
	return "/etc/systemd/system/" + unitName
}

// renderSystemdUnit 生成 systemd 单元文件内容。
func renderSystemdUnit(exePath string) string {
	return `[Unit]
Description=` + DefaultServiceDisplayName + `
Documentation=https://github.com/haoze-evolluling/diting
After=syslog.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=` + exePath + ` -run
Restart=always
RestartSec=10
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
`
}

// removeFile 删除文件，文件不存在时视为成功。
func removeFile(path string) error {
	if err := removePath(path); err != nil && !isNotExist(err) {
		return err
	}
	return nil
}

// resolvedServicePID 报告指定 systemd 单元的主进程 PID（诊断用）。
func resolvedServicePID(ctx context.Context, executor platform.CommandExecutor, unit string) int {
	out, err := runCommand(ctx, executor, "systemctl", "show", unit, "-p", "MainPID", "--value")
	if err != nil {
		return 0
	}
	pid, err := strconv.Atoi(strings.TrimSpace(out))
	if err != nil {
		return 0
	}
	return pid
}
