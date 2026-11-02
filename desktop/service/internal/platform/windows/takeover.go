//go:build windows

package windows

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// WindowsDNSManager 默认 Windows 平台 DNS 接管管理器。
type WindowsDNSManager struct {
	mu               sync.Mutex
	executor         platform.CommandExecutor
	stateStore       platform.StateStore
	active           bool
	adapters         []platform.AdapterState
	version          string
	dnsSetter        func(guidStr string, servers []string) error
	dnsResetter      func(guidStr string) error
	residualResetter func(ctx context.Context) error
}

// NewDNSManager 创建 DNS 接管管理器。
func NewDNSManager(executor platform.CommandExecutor, store platform.StateStore, version string) *WindowsDNSManager {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	if store == nil {
		store = platform.NewFileStateStore("")
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
func (m *WindowsDNSManager) GetTakenOverAdapters() []platform.AdapterState {
	m.mu.Lock()
	defer m.mu.Unlock()
	res := make([]platform.AdapterState, len(m.adapters))
	copy(res, m.adapters)
	return res
}

// FlushDNSCache 刷新 Windows 系统 DNS 解析缓存 (原生 DnsFlushResolverCache)
func (m *WindowsDNSManager) FlushDNSCache(ctx context.Context) error {
	return flushDNSCacheNative()
}

// Takeover 对指定的活动物理网卡执行双栈 DNS 接管 (127.0.0.1 / ::1)
func (m *WindowsDNSManager) Takeover(ctx context.Context, adapters []platform.AdapterInfo) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if len(adapters) == 0 {
		return fmt.Errorf("无有效活动物理网卡可供接管")
	}

	states := make([]platform.AdapterState, 0, len(adapters))
	for _, a := range adapters {
		states = append(states, platform.CleanAdapterState(platform.AdapterState{
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
	persistState := &platform.TakeoverState{
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
	if err := GenerateRestoreScript(states, scriptPath); err != nil {
		// 应急脚本生成失败不阻断接管（网卡仍能正常工作），但绝不能静默：
		// 用户被告知「以管理员运行 restore-dns.bat」时该文件可能根本不存在。
		log.Printf("[Takeover] 生成离线应急恢复脚本失败 (%s): %v", scriptPath, err)
	}

	// 3. 执行 DNS 指向修改 (IPv4: 127.0.0.1, IPv6: ::1)
	for _, a := range states {
		if err := m.applyTakeoverOnAdapter(ctx, a); err != nil {
			// 接管部分网卡失败时，尝试回滚已接管的网卡并清理状态。
			// 回滚失败时绝不能清状态文件：那是下次启动自愈的唯一依据，
			// 丢掉它就等于把网卡永久钉在 127.0.0.1 且无人知晓原始配置。
			if rollbackErr := m.RestoreAdapters(ctx, states); rollbackErr != nil {
				return fmt.Errorf("接管网卡 [%s] 失败: %w（回滚亦失败，已保留状态文件供自愈: %v）", a.Name, err, rollbackErr)
			}
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
func (m *WindowsDNSManager) TakeoverSingle(ctx context.Context, adapter platform.AdapterInfo) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	state := platform.CleanAdapterState(platform.AdapterState{
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
	oldAdapters := make([]platform.AdapterState, len(m.adapters))
	copy(oldAdapters, m.adapters)
	oldActive := m.active

	// 只按 GUID 匹配：显示名不是唯一身份。两块 USB 网卡同叫「以太网」时，
	// 按名匹配会把第一块的原始快照覆盖掉，还原时再也找不到它。
	found := false
	for i := range m.adapters {
		if state.ID != "" && m.adapters[i].ID == state.ID {
			m.adapters[i] = state
			found = true
			break
		}
	}
	if !found {
		m.adapters = append(m.adapters, state)
	}

	persistState := &platform.TakeoverState{
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
	if err := GenerateRestoreScript(m.adapters, scriptPath); err != nil {
		log.Printf("[Takeover] 生成离线应急恢复脚本失败 (%s): %v", scriptPath, err)
	}

	if err := m.applyTakeoverOnAdapter(ctx, state); err != nil {
		// 双栈接管可能只成功了一半（IPv4 已指向 127.0.0.1、IPv6 失败），
		// 仅回滚簿记会让状态文件声称「未接管」而网卡实际仍被劫持。
		// 先按快照把该网卡的 DNS 还原，再回滚内部列表与持久化状态。
		if restoreErr := m.restoreSingleAdapter(ctx, state); restoreErr != nil {
			// 还原失败：保留状态文件，交给下次启动的自愈流程
			m.adapters = oldAdapters
			m.active = oldActive
			healStates := mergeAdapterState(oldAdapters, state)
			if saveErr := m.stateStore.Save(&platform.TakeoverState{
				Active:    true,
				Version:   m.version,
				PID:       os.Getpid(),
				Timestamp: time.Now(),
				Adapters:  healStates,
			}); saveErr != nil {
				return fmt.Errorf("%w（接管回滚失败且状态保存失败: %v）", err, saveErr)
			}
			return fmt.Errorf("%w（接管回滚亦失败，已保留状态文件供自愈: %v）", err, restoreErr)
		}

		m.adapters = oldAdapters
		m.active = oldActive
		if len(oldAdapters) == 0 {
			_ = m.stateStore.Clear()
		} else {
			_ = m.stateStore.Save(&platform.TakeoverState{
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
func (m *WindowsDNSManager) applyTakeoverOnAdapter(ctx context.Context, a platform.AdapterState) error {
	if m.dnsSetter != nil {
		return m.dnsSetter(a.ID, []string{"127.0.0.1", "::1"})
	}
	if !platform.IsDefaultExecutor(m.executor) {
		return nil
	}
	return setAdapterDNSDualStackNative(a.ID, a.Name, []string{"127.0.0.1"}, []string{"::1"})
}

// mergeAdapterState 返回把 state 合并进 base 后的新切片（按 GUID 替换，否则追加）。
func mergeAdapterState(base []platform.AdapterState, state platform.AdapterState) []platform.AdapterState {
	out := append([]platform.AdapterState(nil), base...)
	for i := range out {
		if state.ID != "" && out[i].ID == state.ID {
			out[i] = state
			return out
		}
	}
	return append(out, state)
}

// Restore 将当前被接管的网卡完全还原回原初始配置
func (m *WindowsDNSManager) Restore(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	states := m.adapters
	if len(states) == 0 && m.stateStore != nil {
		if state, loadErr := m.stateStore.Load(); loadErr == nil && state != nil && len(state.Adapters) > 0 {
			states = state.Adapters
		}
	}

	var err error
	if len(states) > 0 {
		err = m.RestoreAdapters(ctx, states)
	}

	if err != nil {
		// 还原失败时保留状态文件与内存快照：它们是下次启动自愈的唯一依据。
		// 先清空再指望兜底清扫，会把原本配置静态 DNS 的网卡抹成 DHCP，
		// 原始地址在快照已毁的情况下永久丢失。
		m.active = true
		if len(m.adapters) == 0 {
			m.adapters = states
		}
		if m.stateStore != nil {
			_ = m.stateStore.Save(&platform.TakeoverState{
				Active:    true,
				Version:   m.version,
				PID:       os.Getpid(),
				Timestamp: time.Now(),
				Adapters:  states,
			})
		}
		_ = m.FlushDNSCache(ctx)
		return err
	}

	m.active = false
	m.adapters = nil
	if m.stateStore != nil {
		_ = m.stateStore.Clear()
	}

	// 还原成功后再做兜底清扫：只清理仍指向回环的残留，不会动正常配置
	_ = m.ResetResidualLoopbackDNS(ctx)
	return nil
}

// RestoreSingle 还原指定单个网卡的 DNS 接管
func (m *WindowsDNSManager) RestoreSingle(ctx context.Context, adapterID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// 按 GUID 优先匹配；显示名仅在唯一命中时才作为回落键。
	// 两块同名网卡时按名匹配会把未选中的那条静默移出状态却从不还原。
	var targets []platform.AdapterState
	for _, a := range m.adapters {
		if a.ID == adapterID {
			targets = append(targets, a)
		}
	}
	if len(targets) == 0 {
		for _, a := range m.adapters {
			if a.Name == adapterID {
				targets = append(targets, a)
			}
		}
	}

	if len(targets) == 0 {
		return nil
	}

	remaining := make([]platform.AdapterState, 0, len(m.adapters))
	for _, a := range m.adapters {
		matched := false
		for _, t := range targets {
			if a.ID == t.ID {
				matched = true
				break
			}
		}
		if !matched {
			remaining = append(remaining, a)
		}
	}

	var restoreErr error
	for _, t := range targets {
		if err := m.restoreSingleAdapter(ctx, t); err != nil {
			// 失败的网卡留在状态里供下次自愈；已成功还原的不再重复记录
			remaining = append(remaining, t)
			restoreErr = err
		}
	}
	if restoreErr != nil {
		m.adapters = remaining
		if len(remaining) == 0 {
			m.active = false
			_ = m.stateStore.Clear()
		} else {
			_ = m.stateStore.Save(&platform.TakeoverState{
				Active:    true,
				Version:   m.version,
				PID:       os.Getpid(),
				Timestamp: time.Now(),
				Adapters:  remaining,
			})
		}
		return restoreErr
	}
	_ = m.FlushDNSCache(ctx)

	m.adapters = remaining
	if len(remaining) == 0 {
		m.active = false
		_ = m.stateStore.Clear()
	} else {
		persistState := &platform.TakeoverState{
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
func (m *WindowsDNSManager) RestoreAdapters(ctx context.Context, adapters []platform.AdapterState) error {
	var lastErr error
	var failed []platform.AdapterState
	for _, a := range adapters {
		if err := m.restoreSingleAdapter(ctx, a); err != nil {
			lastErr = err
			failed = append(failed, a)
		}
	}

	// 还原失败的网卡往往仍停在 127.0.0.1/::1 上（用户侧就是彻底断网），
	// 这里用 netsh 强行拉回 DHCP 先保证有网；快照仍在状态文件里，可再次恢复。
	if len(failed) > 0 && platform.IsDefaultExecutor(m.executor) {
		if sweepErr := forceResetLoopbackAdaptersToDHCP(ctx, failed); sweepErr != nil {
			log.Printf("[接管] 还原失败后的回环 DNS 兜底清理未完成: %v\n", sweepErr)
		}
	}

	_ = m.FlushDNSCache(ctx)
	return lastErr
}

// restoreSingleAdapter 还原单个网卡的 IPv4 与 IPv6 DNS
func (m *WindowsDNSManager) restoreSingleAdapter(ctx context.Context, a platform.AdapterState) error {
	a = platform.CleanAdapterState(a)

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

	if !platform.IsDefaultExecutor(m.executor) {
		return nil
	}

	return setAdapterDNSDualStackNative(a.ID, a.Name, v4Servers, v6Servers)
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
