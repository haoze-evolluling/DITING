package windows

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// DNSManager 定义系统 DNS 接管与还原管理接口
type DNSManager interface {
	Takeover(ctx context.Context, adapters []AdapterInfo) error
	TakeoverSingle(ctx context.Context, adapter AdapterInfo) error
	Restore(ctx context.Context) error
	RestoreSingle(ctx context.Context, adapterID string) error
	RestoreAdapters(ctx context.Context, adapters []AdapterState) error
	ResetResidualLoopbackDNS(ctx context.Context) error
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

// FlushDNSCache 刷新 Windows 系统 DNS 解析缓存 (优先 Win32 原生 DnsFlushResolverCache，异常时回退 ipconfig /flushdns)
func (m *WindowsDNSManager) FlushDNSCache(ctx context.Context) error {
	if isDefaultExecutor(m.executor) {
		if err := flushDNSCacheNative(); err == nil {
			return nil
		}
	}

	// 执行 ipconfig /flushdns 作为可靠兜底
	_, err := m.executor.RunCommand(ctx, "ipconfig", "/flushdns")
	return err
}

// CleanAdapterState 净化网卡快照配置，过滤自身接管的回环地址（127.0.0.0/8、::1 等）
// 若过滤后原始 DNS 为空，则自动将其修正为 DHCP 自动获取，避免恢复为静态 127.0.0.1 导致断网
func CleanAdapterState(a AdapterState) AdapterState {
	cleaned := a
	cleaned.IPv4DNS = FilterLoopbackIPs(a.IPv4DNS)
	cleaned.IPv6DNS = FilterLoopbackIPs(a.IPv6DNS)
	if len(cleaned.IPv4DNS) == 0 {
		cleaned.IPv4DHCP = true
	}
	if len(cleaned.IPv6DNS) == 0 {
		cleaned.IPv6DHCP = true
	}
	return cleaned
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
		states = append(states, CleanAdapterState(AdapterState{
			ID:          a.ID,
			Name:        a.Name,
			Index:       a.Index,
			Description: a.Description,
			IPv4DHCP:    a.IPv4DHCP,
			IPv6DHCP:    a.IPv6DHCP,
			IPv4DNS:     a.IPv4DNS,
			IPv6DNS:     a.IPv6DNS,
		}))
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

// TakeoverSingle 接管指定单个活动物理网卡
func (m *WindowsDNSManager) TakeoverSingle(ctx context.Context, adapter AdapterInfo) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	state := CleanAdapterState(AdapterState{
		ID:          adapter.ID,
		Name:        adapter.Name,
		Index:       adapter.Index,
		Description: adapter.Description,
		IPv4DHCP:    adapter.IPv4DHCP,
		IPv6DHCP:    adapter.IPv6DHCP,
		IPv4DNS:     adapter.IPv4DNS,
		IPv6DNS:     adapter.IPv6DNS,
	})

	// 记录之前的快照，若接管失败则安全回滚
	oldAdapters := make([]AdapterState, len(m.adapters))
	copy(oldAdapters, m.adapters)
	oldActive := m.active

	found := false
	for i, a := range m.adapters {
		if a.ID == adapter.ID || a.Name == adapter.Name {
			m.adapters[i] = state
			found = true
			break
		}
	}
	if !found {
		m.adapters = append(m.adapters, state)
	}

	persistState := &TakeoverState{
		Active:    true,
		Version:   m.version,
		PID:       os.Getpid(),
		Timestamp: time.Now(),
		Adapters:  m.adapters,
	}
	if err := m.stateStore.Save(persistState); err != nil {
		m.adapters = oldAdapters
		return fmt.Errorf("接管前保存状态失败: %w", err)
	}

	scriptPath := filepath.Join(filepath.Dir(m.stateStore.GetFilePath()), "restore-dns.bat")
	_ = GenerateRestoreScript(m.adapters, scriptPath)

	if err := m.applyTakeoverOnAdapter(ctx, state); err != nil {
		// 回滚内部适配器列表及持久化状态
		m.adapters = oldAdapters
		m.active = oldActive
		if len(oldAdapters) == 0 {
			_ = m.stateStore.Clear()
		} else {
			_ = m.stateStore.Save(&TakeoverState{
				Active:    oldActive,
				Version:   m.version,
				PID:       os.Getpid(),
				Timestamp: time.Now(),
				Adapters:  oldAdapters,
			})
		}
		return err
	}

	_ = m.FlushDNSCache(ctx)
	m.active = true
	return nil
}

// applyTakeoverOnAdapter 在指定网卡上设置 IPv4 为 127.0.0.1，IPv6 为 ::1
func (m *WindowsDNSManager) applyTakeoverOnAdapter(ctx context.Context, a AdapterState) error {
	// 1. 优先使用 Windows 原生 API (SetInterfaceDnsSettings) 配置双栈接管地址（无进程拉起开销）
	if isDefaultExecutor(m.executor) {
		if err := setAdapterDNSNative(a.ID, []string{"127.0.0.1", "::1"}); err == nil {
			return nil
		}
	}

	// 2. 备用方案：通过 PowerShell 或 netsh 进行配置
	cmdV4 := fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ServerAddresses @("127.0.0.1","%s")`, a.Index, "::1")
	out, err := m.executor.RunPowerShell(ctx, cmdV4)
	if err != nil {
		// 回退使用 netsh 尝试分别设置 IPv4 与 IPv6 (带 validate=no 避免网络探测挂起)
		_, errV4 := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", "127.0.0.1", "primary", "validate=no")
		_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", "::1", "primary", "validate=no")
		if errV4 != nil {
			return fmt.Errorf("PowerShell 设置失败 (%s), netsh 设置 IPv4 亦失败: %w", out, errV4)
		}
	}
	return nil
}

// Restore 将当前被接管的网卡完全还原回原初始配置
func (m *WindowsDNSManager) Restore(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	var err error
	if len(m.adapters) > 0 {
		err = m.RestoreAdapters(ctx, m.adapters)
	} else if m.stateStore != nil {
		if state, loadErr := m.stateStore.Load(); loadErr == nil && state != nil && len(state.Adapters) > 0 {
			err = m.RestoreAdapters(ctx, state.Adapters)
		}
	}

	m.active = false
	m.adapters = nil
	if m.stateStore != nil {
		_ = m.stateStore.Clear()
	}

	// 无论原状态如何，均主动执行一次全网卡残留回环地址排查兜底
	_ = m.ResetResidualLoopbackDNS(ctx)
	return err
}

// RestoreSingle 还原指定单个网卡的 DNS 接管
func (m *WindowsDNSManager) RestoreSingle(ctx context.Context, adapterID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	var target *AdapterState
	var remaining []AdapterState
	for _, a := range m.adapters {
		if a.ID == adapterID || a.Name == adapterID {
			curr := a
			target = &curr
		} else {
			remaining = append(remaining, a)
		}
	}

	if target == nil {
		return nil
	}

	if err := m.restoreSingleAdapter(ctx, *target); err != nil {
		return err
	}
	_ = m.FlushDNSCache(ctx)

	m.adapters = remaining
	if len(remaining) == 0 {
		m.active = false
		_ = m.stateStore.Clear()
	} else {
		persistState := &TakeoverState{
			Active:    true,
			Version:   m.version,
			PID:       os.Getpid(),
			Timestamp: time.Now(),
			Adapters:  remaining,
		}
		_ = m.stateStore.Save(persistState)
	}
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
	a = CleanAdapterState(a)
	var errs []string

	v4IsDHCP := a.IPv4DHCP || len(a.IPv4DNS) == 0
	v6IsDHCP := a.IPv6DHCP || len(a.IPv6DNS) == 0

	// 1. 若双栈全为 DHCP，一次性通过原生 API 或 ResetServerAddresses 还原
	if v4IsDHCP && v6IsDHCP {
		if isDefaultExecutor(m.executor) {
			if err := resetAdapterDNSNative(a.ID); err == nil {
				return nil
			}
		}

		_, err := m.executor.RunPowerShell(ctx, fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ResetServerAddresses`, a.Index))
		if err != nil {
			_, errV4 := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
			_, errV6 := m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
			if errV4 != nil {
				errs = append(errs, fmt.Sprintf("netsh 恢复 IPv4 DHCP 失败: %v", errV4))
			}
			if errV6 != nil {
				errs = append(errs, fmt.Sprintf("netsh 恢复 IPv6 DHCP 失败: %v", errV6))
			}
		}
		if len(errs) > 0 {
			return fmt.Errorf("还原网卡 [%s] 存在错误: %s", a.Name, strings.Join(errs, "; "))
		}
		return nil
	}

	// 2. 若双栈全为静态配置，优先尝试一次性原生 API 或 PowerShell 还原全部 DNS 地址
	if !v4IsDHCP && !v6IsDHCP {
		allServers := append([]string{}, a.IPv4DNS...)
		allServers = append(allServers, a.IPv6DNS...)
		if isDefaultExecutor(m.executor) {
			if err := setAdapterDNSNative(a.ID, allServers); err == nil {
				return nil
			}
		}

		joined := strings.Join(allServers, `","`)
		psCmd := fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ServerAddresses @("%s")`, a.Index, joined)
		_, err := m.executor.RunPowerShell(ctx, psCmd)
		if err == nil {
			return nil
		}
	}

	// 3. 独立分别处理 IPv4 还原
	if v4IsDHCP {
		_, err := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
		if err != nil {
			errs = append(errs, fmt.Sprintf("恢复 IPv4 DHCP 失败: %v", err))
		}
	} else {
		restoredV4 := false
		if isDefaultExecutor(m.executor) {
			if err := setAdapterDNSNative(a.ID, a.IPv4DNS); err == nil {
				restoredV4 = true
			}
		}
		if !restoredV4 {
			servers := strings.Join(a.IPv4DNS, `","`)
			psCmd := fmt.Sprintf(`Set-DnsClientServerAddress -InterfaceIndex %d -ServerAddresses @("%s")`, a.Index, servers)
			_, err := m.executor.RunPowerShell(ctx, psCmd)
			if err != nil {
				for i, dnsIP := range a.IPv4DNS {
					if i == 0 {
						_, errNetsh := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", dnsIP, "primary", "validate=no")
						if errNetsh != nil {
							errs = append(errs, fmt.Sprintf("netsh 设置静态 IPv4 首选 DNS 失败: %v", errNetsh))
						}
					} else {
						_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "add", "dnsservers", fmt.Sprintf("name=%s", a.Name), dnsIP, fmt.Sprintf("index=%d", i+1), "validate=no")
					}
				}
			}
		}
	}

	// 4. 独立分别处理 IPv6 还原
	if v6IsDHCP {
		_, err := m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "source=dhcp")
		if err != nil {
			errs = append(errs, fmt.Sprintf("恢复 IPv6 DHCP 失败: %v", err))
		}
	} else {
		for i, dnsIP := range a.IPv6DNS {
			if i == 0 {
				_, errNetsh := m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", a.Name), "static", dnsIP, "primary", "validate=no")
				if errNetsh != nil {
					errs = append(errs, fmt.Sprintf("netsh 设置静态 IPv6 首选 DNS 失败: %v", errNetsh))
				}
			} else {
				_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "add", "dnsservers", fmt.Sprintf("name=%s", a.Name), dnsIP, fmt.Sprintf("index=%d", i+1), "validate=no")
			}
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("还原网卡 [%s] 存在错误: %s", a.Name, strings.Join(errs, "; "))
	}
	return nil
}

// ResetResidualLoopbackDNS 扫描系统所有网卡，对任何残留指向 127.0.0.0/8、::1 或未指定地址的 DNS 进行强力重置为 DHCP 自动获取
func (m *WindowsDNSManager) ResetResidualLoopbackDNS(ctx context.Context) error {
	// 生产环境下优先使用 Windows 原生 API 扫描并重置残留回环 DNS，免去启动 PowerShell 进程
	if isDefaultExecutor(m.executor) {
		if err := resetResidualLoopbackDNSNative(ctx, m.executor); err == nil {
			_ = m.FlushDNSCache(ctx)
			return nil
		}
	}

	// 备用方案：通过 PowerShell / netsh 容灾重置
	psScript := `
$ErrorActionPreference = 'SilentlyContinue';
Get-DnsClientServerAddress | Where-Object { ($_.ServerAddresses -contains '127.0.0.1') -or ($_.ServerAddresses -match '^127\.') -or ($_.ServerAddresses -contains '::1') -or ($_.ServerAddresses -contains '0.0.0.0') -or ($_.ServerAddresses -contains '::') } | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue;
    if ($_.InterfaceAlias) {
        netsh interface ipv4 set dnsservers name="$($_.InterfaceAlias)" source=dhcp 2>$null;
        netsh interface ipv6 set dnsservers name="$($_.InterfaceAlias)" source=dhcp 2>$null;
    }
};
Clear-DnsClientCache -ErrorAction SilentlyContinue;
`
	_, err := m.executor.RunPowerShell(ctx, psScript)
	if err != nil {
		// PowerShell 异常时使用 netsh 容灾兜底解析并重置
		_ = m.resetResidualLoopbackDNSViaNetsh(ctx)
	}
	_ = m.FlushDNSCache(ctx)
	return err
}

func (m *WindowsDNSManager) resetResidualLoopbackDNSViaNetsh(ctx context.Context) error {
	outV4, _ := m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "show", "dnsservers")
	for _, name := range parseNetshInterfacesWithLoopback(outV4) {
		_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv4", "set", "dnsservers", fmt.Sprintf("name=%s", name), "source=dhcp")
	}

	outV6, _ := m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "show", "dnsservers")
	for _, name := range parseNetshInterfacesWithLoopback(outV6) {
		_, _ = m.executor.RunCommand(ctx, "netsh", "interface", "ipv6", "set", "dnsservers", fmt.Sprintf("name=%s", name), "source=dhcp")
	}
	return nil
}

// parseNetshInterfacesWithLoopback 从 netsh 输出中提取配置了回环地址 DNS 的网卡别名
func parseNetshInterfacesWithLoopback(output string) []string {
	var result []string
	lines := strings.Split(output, "\n")
	var currentInterface string
	hasLoopback := false

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Configuration for interface \"") {
			if currentInterface != "" && hasLoopback {
				result = append(result, currentInterface)
			}
			currentInterface = strings.TrimSuffix(strings.TrimPrefix(trimmed, "Configuration for interface \""), "\"")
			hasLoopback = false
			continue
		}
		if strings.HasPrefix(trimmed, "接口 \"") {
			if currentInterface != "" && hasLoopback {
				result = append(result, currentInterface)
			}
			currentInterface = strings.TrimSuffix(strings.TrimPrefix(trimmed, "接口 \""), "\" 的配置")
			currentInterface = strings.TrimSuffix(currentInterface, "\"")
			hasLoopback = false
			continue
		}

		if currentInterface != "" && (strings.Contains(trimmed, "127.") || strings.Contains(trimmed, "::1")) {
			hasLoopback = true
		}
	}
	if currentInterface != "" && hasLoopback {
		result = append(result, currentInterface)
	}
	return result
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

	for _, raw := range adapters {
		a := CleanAdapterState(raw)
		sb.WriteString(fmt.Sprintf("echo 正在恢复适配器 [%s] ...\r\n", a.Name))
		if a.IPv4DHCP || len(a.IPv4DNS) == 0 {
			sb.WriteString(fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" source=dhcp\r\n", a.Name))
		} else {
			for i, dnsIP := range a.IPv4DNS {
				if i == 0 {
					sb.WriteString(fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" static %s primary validate=no\r\n", a.Name, dnsIP))
				} else {
					sb.WriteString(fmt.Sprintf("netsh interface ipv4 add dnsservers name=\"%s\" %s index=%d validate=no\r\n", a.Name, dnsIP, i+1))
				}
			}
		}

		if a.IPv6DHCP || len(a.IPv6DNS) == 0 {
			sb.WriteString(fmt.Sprintf("netsh interface ipv6 set dnsservers name=\"%s\" source=dhcp\r\n", a.Name))
		} else {
			for i, dnsIP := range a.IPv6DNS {
				if i == 0 {
					sb.WriteString(fmt.Sprintf("netsh interface ipv6 set dnsservers name=\"%s\" static %s primary validate=no\r\n", a.Name, dnsIP))
				} else {
					sb.WriteString(fmt.Sprintf("netsh interface ipv6 add dnsservers name=\"%s\" %s index=%d validate=no\r\n", a.Name, dnsIP, i+1))
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
