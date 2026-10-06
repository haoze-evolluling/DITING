package windows

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWindowsDNSManager_TakeoverAndRestore(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)
	executor := &mockExecutor{}

	mgr := NewDNSManager(executor, store, "0.1.0-test")

	adapters := []AdapterInfo{
		{
			ID:          "{GUID-WLAN}",
			Name:        "WLAN",
			Index:       8,
			Description: "Wi-Fi",
			Status:      "Up",
			Gateway:     "192.168.1.1",
			IPv4DHCP:    true,
			IPv6DHCP:    true,
			IPv4DNS:     []string{"192.168.1.1"},
			IPv6DNS:     []string{"fd12::1"},
			IsPhysical:  true,
		},
	}

	// 1. 接管测试
	if err := mgr.Takeover(context.Background(), adapters); err != nil {
		t.Fatalf("Takeover failed: %v", err)
	}

	if !mgr.IsTakeoverActive() {
		t.Errorf("expected takeover active")
	}
	if len(mgr.GetTakenOverAdapters()) != 1 {
		t.Errorf("expected 1 taken over adapter")
	}

	// 验证持久化状态存在
	savedState, err := store.Load()
	if err != nil || savedState == nil || !savedState.Active {
		t.Fatalf("expected active saved state, got err=%v, state=%+v", err, savedState)
	}

	// 验证应急脚本生成
	batPath := filepath.Join(tmpDir, "restore-dns.bat")
	batBytes, err := os.ReadFile(batPath)
	if err != nil {
		t.Fatalf("restore-dns.bat was not created: %v", err)
	}
	batContent := string(batBytes)
	if !strings.Contains(batContent, "netsh interface ipv4 set dnsservers name=\"WLAN\" source=dhcp") {
		t.Errorf("bat script missing expected DHCP restore command: %s", batContent)
	}

	// 2. 还原测试
	if err := mgr.Restore(context.Background()); err != nil {
		t.Fatalf("Restore failed: %v", err)
	}

	if mgr.IsTakeoverActive() {
		t.Errorf("expected takeover inactive")
	}

	clearedState, err := store.Load()
	if err != nil || clearedState != nil {
		t.Fatalf("expected state cleared, got err=%v, state=%+v", err, clearedState)
	}
}

func TestWindowsDNSManager_StaticAdapterRestore(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)
	executor := &mockExecutor{}

	mgr := NewDNSManager(executor, store, "0.1.0-test")

	adapters := []AdapterInfo{
		{
			ID:          "{GUID-STATIC}",
			Name:        "以太网",
			Index:       16,
			Description: "Ethernet",
			Status:      "Up",
			Gateway:     "192.168.1.1",
			IPv4DHCP:    false,
			IPv6DHCP:    false,
			IPv4DNS:     []string{"8.8.8.8", "8.8.4.4"},
			IPv6DNS:     []string{"2001:4860:4860::8888"},
			IsPhysical:  true,
		},
	}

	if err := mgr.Takeover(context.Background(), adapters); err != nil {
		t.Fatalf("Takeover failed: %v", err)
	}

	// 检查应急脚本中是否包含了静态 IP 的配置命令
	batPath := filepath.Join(tmpDir, "restore-dns.bat")
	batBytes, err := os.ReadFile(batPath)
	if err != nil {
		t.Fatalf("read bat failed: %v", err)
	}
	batContent := string(batBytes)
	if !strings.Contains(batContent, "static 8.8.8.8 primary") {
		t.Errorf("expected static 8.8.8.8 primary in bat script, got: %s", batContent)
	}
	if !strings.Contains(batContent, "8.8.4.4 index=2") {
		t.Errorf("expected secondary DNS in bat script, got: %s", batContent)
	}

	if err := mgr.Restore(context.Background()); err != nil {
		t.Fatalf("Restore failed: %v", err)
	}
}

func TestWindowsDNSManager_TakeoverFailureRollback(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)

	// 模拟执行失败的执行器
	failExecutor := &mockExecutor{
		psErr:  fmt.Errorf("access denied"),
		cmdErr: fmt.Errorf("access denied"),
	}

	mgr := NewDNSManager(failExecutor, store, "0.1.0-test")

	adapters := []AdapterInfo{
		{
			ID:         "{GUID-FAIL}",
			Name:       "FailAdapter",
			Index:      2,
			IPv4DHCP:   true,
			IsPhysical: true,
			Status:     "Up",
			Gateway:    "192.168.1.1",
		},
	}

	err := mgr.Takeover(context.Background(), adapters)
	if err == nil {
		t.Fatalf("expected Takeover to fail on command error")
	}

	if mgr.IsTakeoverActive() {
		t.Errorf("takeover should not be active after failure")
	}
}
