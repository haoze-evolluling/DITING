package windows

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	dnsapiMod                 = syscall.NewLazyDLL("dnsapi.dll")
	procDnsFlushResolverCache = dnsapiMod.NewProc("DnsFlushResolverCache")
)

// DNSManager 定义系统 DNS 接管与还原管理接口
type DNSManager interface {
	Takeover(ctx context.Context, adapters []AdapterInfo) error
	Restore(ctx context.Context) error
	RestoreAdapters(ctx context.Context, adapters []AdapterState) error
	IsTakeoverActive() bool
	GetTakenOverAdapters() []AdapterState
	FlushDNSCache(ctx context.Context) error
}

// WindowsDNSManager 默认 Windows 平台 DNS 接管管理器
type WindowsDNSManager struct {
	mu         sync.Mutex
	executor   CommandExecutor
	stateStore StateStore
	active     bool
	adapters   []AdapterState
	version    string
}

// NewDNSManager 创建 DNS 接管管理器
func NewDNSManager(executor CommandExecutor, store StateStore, version string) *WindowsDNSManager {
	if executor == nil {
		executor = NewDefaultExecutor()
	}
	if store == nil {
		store = NewFileStateStore("")
	}
	if version == "" {
		version = "dev"
	}
	return &WindowsDNSManager{
		executor:   executor,
		stateStore: store,
		version:    version,
	}
}

// IsTakeoverActive 获取当前是否处于接管状态
func (m *WindowsDNSManager) IsTakeoverActive() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.active
}

// GetTakenOverAdapters 获取当前被接管的网卡列表
func (m *WindowsDNSManager) GetTakenOverAdapters() []AdapterState {
	m.mu.Lock()
	defer m.mu.Unlock()
	res := make([]AdapterState, len(m.adapters))
	copy(res, m.adapters)
	return res
}

// FlushDNSCache 刷新 Windows 系统 DNS 解析缓存 (Win32 DnsFlushResolverCache + ipconfig /flushdns)
func (m *WindowsDNSManager) FlushDNSCache(ctx context.Context) error {
	// 优先调用 Win32 动态库底层 API
	if procDnsFlushResolverCache.Find() == nil {
		_, _, _ = procDnsFlushResolverCache.Call()
	}

	// 执行 ipconfig /flushdns 作为可靠兜底
	_, err := m.executor.RunCommand(ctx, "ipconfig", "/flushdns")
	return err
}

// Takeover 对指定的活动物理网卡执行双栈 DNS 接管 (127.0.0.1 / ::1)
func (m *WindowsDNSManager) Takeover(ctx context.Context, adapters []AdapterInfo) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if len(adapters) == 0 {
		return fmt.Errorf("无有效活动物理网卡可供接管")
	}

	states := make([]AdapterState, 0, len(adapters))
	for _, a := range adapters {
		states = append(states, AdapterState{
			ID:          a.ID,
			Name:        a.Name,
			Index:       a.Index,
			Description: a.Description,
			IPv4DHCP:    a.IPv4DHCP,
			IPv6DHCP:    a.IPv6DHCP,
			IPv4DNS:     a.IPv4DNS,
			IPv6DNS:     a.IPv6DNS,
		})
	}

	// 1. 持久化记录接管状态至 dns_state.json
	persistState := &TakeoverState{
		Active:    true,
		Version:   m.version,
		PID:       os.Getpid(),
		Timestamp: time.Now(),
		Adapters:  states,
	}
	if err := m.stateStore.Save(persistState); err != nil {
		return fmt.Errorf("接管前保存状态失败: %w", err)
	}

	// 2. 生成离线应急恢复脚本 restore-dns.bat
	scriptPath := filepath.Join(filepath.Dir(m.stateStore.GetFilePath()), "restore-dns.bat")
	_ = GenerateRestoreScript(states, scriptPath)

	// 3. 执行 DNS 指向修改 (IPv4: 127.0.0.1, IPv6: ::1)
	for _, a := range states {
		if err := m.applyTakeoverOnAdapter(ctx, a); err != nil {
			// 接管部分网卡失败时，尝试回滚已接管的网卡并清理状态
			_ = m.RestoreAdapters(ctx, states)
			_ = m.stateStore.Clear()
			return fmt.Errorf("接管网卡 [%s] 失败: %w", a.Name, err)
		}
	}

	// 4. 刷新系统解析缓存
	_ = m.FlushDNSCache(ctx)

	m.active = true
	m.adapters = states
	return nil
}

// applyTakeoverOnAdapter 在指定网卡上设置 IPv4 为 127.0.0.1，IPv6 为 ::1
func (m *WindowsDNSManager) applyTakeoverOnAdapter(ctx context.Context, a AdapterState) error {
	// 使用 netsh / PowerShell 设置 IPv4
	cmdV4 := fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ServerAddresses @("127.0.0.1","%s")`, a.Index, "::1")
	out, err := m.executor.RunPowerShell(ctx, cmdV4)
	if err != nil {
		// 回退使用 netsh 尝试分别设置 IPv4 与 IPv6
		_, errV4 := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", "127.0.0.1", "primary")
		_, errV6 := m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", "::1", "primary")
		if errV4 != nil && errV6 != nil {
			return fmt.Errorf("PowerShell 设置失败 (%s), netsh 设置 IPv4/IPv6 亦失败: %v / %v", out, errV4, errV6)
		}
	}
	return nil
}

// Restore 将当前被接管的网卡完全还原回原初始配置
func (m *WindowsDNSManager) Restore(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if !m.active && len(m.adapters) == 0 {
		return nil
	}

	err := m.RestoreAdapters(ctx, m.adapters)
	if err != nil {
		return err
	}

	m.active = false
	m.adapters = nil
	_ = m.stateStore.Clear()
	return nil
}

// RestoreAdapters 批量还原指定网卡列表的 DNS 配置
func (m *WindowsDNSManager) RestoreAdapters(ctx context.Context, adapters []AdapterState) error {
	var lastErr error
	for _, a := range adapters {
		if err := m.restoreSingleAdapter(ctx, a); err != nil {
			lastErr = err
		}
	}

	_ = m.FlushDNSCache(ctx)
	return lastErr
}

// restoreSingleAdapter 还原单个网卡的 IPv4 与 IPv6 DNS
func (m *WindowsDNSManager) restoreSingleAdapter(ctx context.Context, a AdapterState) error {
	var errs []string

	// 还原 IPv4
	if a.IPv4DHCP || len(a.IPv4DNS) == 0 {
		// 恢复为 DHCP
		_, err := m.executor.RunPowerShell(ctx, fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ResetServerAddresses`, a.Index))
		if err != nil {
			_, errNetsh := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
			if errNetsh != nil {
				errs = append(errs, fmt.Sprintf("恢复 IPv4 DHCP 失败: %v", errNetsh))
			}
		}
	} else {
		// 恢复静态 IPv4 DNS
		servers := strings.Join(a.IPv4DNS, `","`)
		psCmd := fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ServerAddresses @("%s")`, a.Index, servers)
		_, err := m.executor.RunPowerShell(ctx, psCmd)
		if err != nil {
			// 回退 netsh 逐条配置
			for i, dnsIP := range a.IPv4DNS {
				if i == 0 {
					_, errNetsh := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", dnsIP, "primary")
					if errNetsh != nil {
						errs = append(errs, fmt.Sprintf("netsh 设置静态 IPv4 首选 DNS 失败: %v", errNetsh))
					}
				} else {
					_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "add", "dnsservers", fmt.Sprintf("name=%s", a.Name), dnsIP, fmt.Sprintf("index=%d", i+1))
				}
			}
		}
	}

	// 还原 IPv6
	if a.IPv6DHCP || len(a.IPv6DNS) == 0 {
		_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
	} else {
		for i, dnsIP := range a.IPv6DNS {
			if i == 0 {
				_, errNetsh := m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", dnsIP, "primary")
				if errNetsh != nil {
					errs = append(errs, fmt.Sprintf("netsh 设置静态 IPv6 首选 DNS 失败: %v", errNetsh))
				}
			} else {
				_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "add", "dnsservers", fmt.Sprintf("name=%s", a.Name), dnsIP, fmt.Sprintf("index=%d", i+1))
			}
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("还原网卡 [%s] 存在错误: %s", a.Name, strings.Join(errs, "; "))
	}
	return nil
}

// GenerateRestoreScript 生成独立离线恢复脚本 restore-dns.bat
func GenerateRestoreScript(adapters []AdapterState, outputPath string) error {
	var sb strings.Builder
	sb.WriteString("@echo off\r\n")
	sb.WriteString("chcp 65001 >nul\r\n")
	sb.WriteString("echo ================================================================\r\n")
	sb.WriteString("echo   谛听 (DITING) 紧急离线 DNS 还原脚本\r\n")
	sb.WriteString(fmt.Sprintf("echo   生成时间: %s\r\n", time.Now().Format("2006-01-02 15:04:05")))
	sb.WriteString("echo ================================================================\r\n\r\n")
	sb.WriteString("net session >nul 2>&1\r\n")
	sb.WriteString("if %errorlevel% neq 0 (\r\n")
	sb.WriteString("    echo [错误] 请右键点击此批处理脚本，选择【以管理员身份运行】！\r\n")
	sb.WriteString("    pause\r\n")
	sb.WriteString("    exit /b 1\r\n")
	sb.WriteString(")\r\n\r\n")
	sb.WriteString("echo [1/2] 正在还原网卡 DNS 配置...\r\n")

	for _, a := range adapters {
		sb.WriteString(fmt.Sprintf("echo 正在恢复适配器 [%s] ...\r\n", a.Name))
		if a.IPv4DHCP || len(a.IPv4DNS) == 0 {
			sb.WriteString(fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" source=dhcp\r\n", a.Name))
		} else {
			for i, dnsIP := range a.IPv4DNS {
				if i == 0 {
					sb.WriteString(fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" static %s primary\r\n", a.Name, dnsIP))
				} else {
					sb.WriteString(fmt.Sprintf("netsh interface ipv4 add dnsservers name=\"%s\" %s index=%d\r\n", a.Name, dnsIP, i+1))
				}
			}
		}

		if a.IPv6DHCP || len(a.IPv6DNS) == 0 {
			sb.WriteString(fmt.Sprintf("netsh interface ipv6 set dnsservers name=\"%s\" source=dhcp\r\n", a.Name))
		} else {
			for i, dnsIP := range a.IPv6DNS {
				if i == 0 {
					sb.WriteString(fmt.Sprintf("netsh interface ipv6 set dnsservers name=\"%s\" static %s primary\r\n", a.Name, dnsIP))
				} else {
					sb.WriteString(fmt.Sprintf("netsh interface ipv6 add dnsservers name=\"%s\" %s index=%d\r\n", a.Name, dnsIP, i+1))
				}
			}
		}
	}

	sb.WriteString("\r\necho [2/2] 正在刷新系统 DNS 解析缓存...\r\n")
	sb.WriteString("ipconfig /flushdns\r\n\r\n")
	sb.WriteString("echo ================================================================\r\n")
	sb.WriteString("echo 系统 DNS 设置已完全恢复初始状态。\r\n")
	sb.WriteString("echo ================================================================\r\n")
	sb.WriteString("pause\r\n")

	dir := filepath.Dir(outputPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	return os.WriteFile(outputPath, []byte(sb.String()), 0644)
}
