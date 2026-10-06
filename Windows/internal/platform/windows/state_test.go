package windows

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type mockRestorer struct {
	restored []AdapterState
	err      error
}

func (m *mockRestorer) RestoreAdapters(ctx context.Context, adapters []AdapterState) error {
	m.restored = adapters
	return m.err
}

func TestFileStateStore_SaveAndLoad(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)

	// 文件未创建前 Load 应返回 nil, nil
	initial, err := store.Load()
	if err != nil {
		t.Fatalf("expected nil error on nonexistent file, got %v", err)
	}
	if initial != nil {
		t.Fatalf("expected nil state, got %+v", initial)
	}

	state := &TakeoverState{
		Active:    true,
		Version:   "1.0.0",
		PID:       12345,
		Timestamp: time.Now().Truncate(time.Second),
		Adapters: []AdapterState{
			{
				ID:          "{GUID-TEST}",
				Name:        "WLAN",
				Index:       8,
				Description: "Wi-Fi Adapter",
				IPv4DHCP:    true,
				IPv6DHCP:    false,
				IPv4DNS:     []string{"192.168.1.1"},
				IPv6DNS:     []string{"2001:db8::1"},
			},
		},
	}

	if err := store.Save(state); err != nil {
		t.Fatalf("Save failed: %v", err)
	}

	loaded, err := store.Load()
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	if loaded == nil || !loaded.Active || loaded.PID != 12345 || len(loaded.Adapters) != 1 {
		t.Fatalf("loaded state mismatch: %+v", loaded)
	}
	if loaded.Adapters[0].Name != "WLAN" {
		t.Errorf("adapter name mismatch: got %s, want WLAN", loaded.Adapters[0].Name)
	}

	// 测试 Clear
	if err := store.Clear(); err != nil {
		t.Fatalf("Clear failed: %v", err)
	}

	cleared, err := store.Load()
	if err != nil || cleared != nil {
		t.Fatalf("expected nil after clear, got err=%v, state=%+v", err, cleared)
	}
}

func TestFileStateStore_CheckAndSelfHeal(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)

	// 1. 无残留文件时，CheckAndSelfHeal 返回 false
	restorer := &mockRestorer{}
	healed, err := store.CheckAndSelfHeal(context.Background(), restorer)
	if err != nil || healed {
		t.Fatalf("expected healed=false, got %v (err=%v)", healed, err)
	}

	// 2. 模拟写入残留激活状态
	state := &TakeoverState{
		Active:    true,
		Version:   "0.1.0",
		PID:       99999, // 死亡进程
		Timestamp: time.Now(),
		Adapters: []AdapterState{
			{ID: "{GUID-A}", Name: "以太网", Index: 1, IPv4DHCP: true},
		},
	}
	if err := store.Save(state); err != nil {
		t.Fatalf("Save state failed: %v", err)
	}

	// 3. 执行自愈检查，应触发 RestoreAdapters 并清理状态文件
	healed, err = store.CheckAndSelfHeal(context.Background(), restorer)
	if err != nil {
		t.Fatalf("CheckAndSelfHeal returned error: %v", err)
	}
	if !healed {
		t.Fatalf("expected healed=true")
	}
	if len(restorer.restored) != 1 || restorer.restored[0].Name != "以太网" {
		t.Fatalf("restorer did not receive adapter: %+v", restorer.restored)
	}

	// 4. 再次检查，文件应已被清理
	if _, err := os.Stat(stateFile); !os.IsNotExist(err) {
		t.Fatalf("state file should be removed after self-heal")
	}
}
