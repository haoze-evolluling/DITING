package windows

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
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
	mu               sync.Mutex
	executor         CommandExecutor
	stateStore       StateStore
	active           bool
	adapters         []AdapterState
	version          string
	dnsSetter        func(guidStr string, servers []string) error
	dnsResetter      func(guidStr string) error
	residualResetter func(ctx context.Context) error
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

// FlushDNSCache 刷新 Windows 系统 DNS 解析缓存 (原生 DnsFlushResolverCache)
func (m *WindowsDNSManager) FlushDNSCache(ctx context.Context) error {
	return flushDNSCacheNative()
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
	if m.dnsSetter != nil {
		return m.dnsSetter(a.ID, []string{"127.0.0.1", "::1"})
	}
	if !isDefaultExecutor(m.executor) {
		return nil
	}
	return setAdapterDNSDualStackNative(a.ID, []string{"127.0.0.1"}, []string{"::1"})
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

	v4IsDHCP := a.IPv4DHCP || len(a.IPv4DNS) == 0
	v6IsDHCP := a.IPv6DHCP || len(a.IPv6DNS) == 0

	var v4Servers []string
	if !v4IsDHCP {
		v4Servers = a.IPv4DNS
	}
	var v6Servers []string
	if !v6IsDHCP {
		v6Servers = a.IPv6DNS
	}

	if m.dnsSetter != nil {
		all := append([]string{}, v4Servers...)
		all = append(all, v6Servers...)
		if len(all) > 0 {
			return m.dnsSetter(a.ID, all)
		}
		if m.dnsResetter != nil {
			return m.dnsResetter(a.ID)
		}
		return nil
	}
	if v4IsDHCP && v6IsDHCP && m.dnsResetter != nil {
		return m.dnsResetter(a.ID)
	}

	if !isDefaultExecutor(m.executor) {
		return nil
	}

	return setAdapterDNSDualStackNative(a.ID, v4Servers, v6Servers)
}

// ResetResidualLoopbackDNS 扫描系统所有网卡，对任何残留指向 127.0.0.0/8、::1 或未指定地址的 DNS 进行强力重置为 DHCP 自动获取
func (m *WindowsDNSManager) ResetResidualLoopbackDNS(ctx context.Context) error {
	var err error
	if m.residualResetter != nil {
		err = m.residualResetter(ctx)
	} else {
		err = resetResidualLoopbackDNSNative(ctx)
	}
	_ = m.FlushDNSCache(ctx)
	return err
}
