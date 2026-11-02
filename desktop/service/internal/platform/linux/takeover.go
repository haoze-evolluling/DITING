//go:build linux

package linux

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// LinuxDNSManager Linux 平台 DNS 接管管理器。
//
// 与 Windows 实现语义一一对应：接管前落盘快照并生成离线恢复脚本，
// 任一网卡接管失败即回滚已生效部分并清理状态；还原时按快照恢复，
// 并在最后执行一次全网卡回环残留兜底排查。
type LinuxDNSManager struct {
	mu         sync.Mutex
	executor   platform.CommandExecutor
	stateStore platform.StateStore
	backend    dnsBackend
	active     bool
	adapters   []platform.AdapterState
	version    string
}

// NewDNSManager 创建 DNS 接管管理器。
func NewDNSManager(executor platform.CommandExecutor, store platform.StateStore, version string) *LinuxDNSManager {
	if executor == nil {
		executor = platform.NewDefaultExecutor()
	}
	if store == nil {
		store = platform.NewFileStateStore("")
	}
	if version == "" {
		version = "dev"
	}
	return &LinuxDNSManager{
		executor:   executor,
		stateStore: store,
		backend:    detectBackend(context.Background(), executor),
		version:    version,
	}
}

// IsTakeoverActive 获取当前是否处于接管状态
func (m *LinuxDNSManager) IsTakeoverActive() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.active
}

// GetTakenOverAdapters 获取当前被接管的网卡列表
func (m *LinuxDNSManager) GetTakenOverAdapters() []platform.AdapterState {
	m.mu.Lock()
	defer m.mu.Unlock()
	res := make([]platform.AdapterState, len(m.adapters))
	copy(res, m.adapters)
	return res
}

// FlushDNSCache 刷新系统 DNS 解析缓存
func (m *LinuxDNSManager) FlushDNSCache(ctx context.Context) error {
	return m.backend.Flush(ctx)
}

// Takeover 对指定的活动物理网卡执行双栈 DNS 接管 (127.0.0.1 / ::1)
func (m *LinuxDNSManager) Takeover(ctx context.Context, adapters []platform.AdapterInfo) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if len(adapters) == 0 {
		return fmt.Errorf("无有效活动物理网卡可供接管")
	}

	states := adapterInfosToStates(adapters)

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

	scriptPath := filepath.Join(filepath.Dir(m.stateStore.GetFilePath()), "restore-dns.sh")
	_ = GenerateRestoreScript(m.backend.Kind(), states, scriptPath)

	if err := m.backend.Apply(ctx, adapters); err != nil {
		if restoreErr := m.backend.Restore(ctx, states); restoreErr != nil {
			// 回滚没成功时保留状态文件，下次启动仍可据此还原，不能把唯一线索抹掉
			return fmt.Errorf("接管网卡 DNS 失败: %w（回滚亦失败: %v，已保留状态文件）", err, restoreErr)
		}
		_ = m.stateStore.Clear()
		return fmt.Errorf("接管网卡 DNS 失败: %w", err)
	}

	_ = m.FlushDNSCache(ctx)

	m.active = true
	m.adapters = states
	return nil
}

// TakeoverSingle 接管指定单个活动物理网卡
func (m *LinuxDNSManager) TakeoverSingle(ctx context.Context, adapter platform.AdapterInfo) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	state := adapterInfoToState(adapter)

	oldAdapters := make([]platform.AdapterState, len(m.adapters))
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

	scriptPath := filepath.Join(filepath.Dir(m.stateStore.GetFilePath()), "restore-dns.sh")
	_ = GenerateRestoreScript(m.backend.Kind(), m.adapters, scriptPath)

	if err := m.backend.Apply(ctx, []platform.AdapterInfo{adapter}); err != nil {
		// 回滚已生效的系统修改：后端契约要求 Apply 失败不留半成品，
		// 但单卡路径此前完全没有补偿，DNS 会永久指向 127.0.0.1
		restoreErr := m.backend.Restore(ctx, []platform.AdapterState{state})
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
		if restoreErr != nil {
			return fmt.Errorf("%w（回滚亦失败: %v）", err, restoreErr)
		}
		return err
	}

	_ = m.FlushDNSCache(ctx)
	m.active = true
	return nil
}

// Restore 将当前被接管的网卡完全还原回原初始配置
func (m *LinuxDNSManager) Restore(ctx context.Context) error {
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
func (m *LinuxDNSManager) RestoreSingle(ctx context.Context, adapterID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// 同名多条目必须全部命中并一并还原：旧实现只保留最后一条，其余匹配项
	// 既不还原也不留在 remaining，函数却返回成功，状态文件与实况脱节。
	var targets []platform.AdapterState
	var remaining []platform.AdapterState
	for _, a := range m.adapters {
		if a.ID == adapterID || a.Name == adapterID {
			targets = append(targets, a)
		} else {
			remaining = append(remaining, a)
		}
	}

	if len(targets) == 0 {
		return nil
	}

	if err := m.backend.Restore(ctx, targets); err != nil {
		return err
	}
	_ = m.FlushDNSCache(ctx)

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
	return nil
}

// RestoreAdapters 批量还原指定网卡列表的 DNS 配置
func (m *LinuxDNSManager) RestoreAdapters(ctx context.Context, adapters []platform.AdapterState) error {
	cleaned := make([]platform.AdapterState, 0, len(adapters))
	for _, a := range adapters {
		cleaned = append(cleaned, platform.CleanAdapterState(a))
	}

	err := m.backend.Restore(ctx, cleaned)
	_ = m.FlushDNSCache(ctx)
	return err
}

// ResetResidualLoopbackDNS 扫描系统所有网卡，对任何残留指向 127.0.0.0/8
// 或 ::1 的 DNS 配置执行兜底还原。
func (m *LinuxDNSManager) ResetResidualLoopbackDNS(ctx context.Context) error {
	scanner := &NativeAdapterScanner{}
	adapters, err := scanner.ScanAll(ctx)
	if err != nil {
		return err
	}

	var residual []platform.AdapterState
	for _, a := range adapters {
		if !a.HasResidualLoopback {
			continue
		}
		residual = append(residual, adapterInfoToState(a))
	}
	if len(residual) == 0 {
		return nil
	}

	err = m.backend.Restore(ctx, residual)
	_ = m.FlushDNSCache(ctx)
	return err
}

// adapterInfoToState 将扫得的网卡信息转换成接管前快照条目。
func adapterInfoToState(a platform.AdapterInfo) platform.AdapterState {
	return platform.CleanAdapterState(platform.AdapterState{
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

// adapterInfosToStates 批量转换网卡信息为快照条目。
func adapterInfosToStates(adapters []platform.AdapterInfo) []platform.AdapterState {
	states := make([]platform.AdapterState, 0, len(adapters))
	for _, a := range adapters {
		states = append(states, adapterInfoToState(a))
	}
	return states
}
