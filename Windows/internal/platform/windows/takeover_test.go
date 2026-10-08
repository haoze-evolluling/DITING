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
	if !strings.Contains(batContent, "static 2001:4860:4860::8888 primary") {
		t.Errorf("expected static IPv6 2001:4860:4860::8888 in bat script, got: %s", batContent)
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
		cmdErr: fmt.Errorf("access denied"),
	}

	mgr := NewDNSManager(failExecutor, store, "0.1.0-test")
	mgr.dnsSetter = func(guidStr string, servers []string) error {
		return fmt.Errorf("access denied")
	}

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

func TestWindowsDNSManager_TakeoverSingleAndRestoreSingle(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)
	executor := &mockExecutor{}

	mgr := NewDNSManager(executor, store, "0.1.0-test")

	adapter1 := AdapterInfo{
		ID:         "{GUID-1}",
		Name:       "Adapter1",
		Index:      1,
		IPv4DHCP:   true,
		IsPhysical: true,
		Status:     "Up",
	}
	adapter2 := AdapterInfo{
		ID:         "{GUID-2}",
		Name:       "Adapter2",
		Index:      2,
		IPv4DHCP:   true,
		IsPhysical: true,
		Status:     "Up",
	}

	// 1. 接管第一个网卡
	if err := mgr.TakeoverSingle(context.Background(), adapter1); err != nil {
		t.Fatalf("TakeoverSingle 1 failed: %v", err)
	}
	if !mgr.IsTakeoverActive() || len(mgr.GetTakenOverAdapters()) != 1 {
		t.Fatalf("expected 1 active adapter")
	}

	// 2. 接管第二个网卡
	if err := mgr.TakeoverSingle(context.Background(), adapter2); err != nil {
		t.Fatalf("TakeoverSingle 2 failed: %v", err)
	}
	if len(mgr.GetTakenOverAdapters()) != 2 {
		t.Fatalf("expected 2 active adapters")
	}

	// 3. 还原第一个网卡
	if err := mgr.RestoreSingle(context.Background(), "{GUID-1}"); err != nil {
		t.Fatalf("RestoreSingle 1 failed: %v", err)
	}
	if !mgr.IsTakeoverActive() || len(mgr.GetTakenOverAdapters()) != 1 {
		t.Fatalf("expected 1 active adapter remaining")
	}
	if mgr.GetTakenOverAdapters()[0].ID != "{GUID-2}" {
		t.Fatalf("expected Adapter2 remaining")
	}

	// 4. 还原第二个网卡
	if err := mgr.RestoreSingle(context.Background(), "{GUID-2}"); err != nil {
		t.Fatalf("RestoreSingle 2 failed: %v", err)
	}
	if mgr.IsTakeoverActive() || len(mgr.GetTakenOverAdapters()) != 0 {
		t.Fatalf("expected 0 active adapters, fully restored")
	}
}

func TestWindowsDNSManager_TakeoverSingleRollback(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "dns_state.json")
	store := NewFileStateStore(stateFile)

	failExecutor := &mockExecutor{
		cmdErr: fmt.Errorf("access denied"),
	}

	mgr := NewDNSManager(failExecutor, store, "0.1.0-test")
	mgr.dnsSetter = func(guidStr string, servers []string) error {
		return fmt.Errorf("access denied")
	}

	adapter := AdapterInfo{
		ID:         "{GUID-FAIL}",
		Name:       "FailSingle",
		Index:      5,
		IPv4DHCP:   true,
		IsPhysical: true,
		Status:     "Up",
	}

	err := mgr.TakeoverSingle(context.Background(), adapter)
	if err == nil {
		t.Fatalf("expected TakeoverSingle to fail on command error")
	}

	if mgr.IsTakeoverActive() {
		t.Errorf("takeover should not be active after single failure")
	}
	if len(mgr.GetTakenOverAdapters()) != 0 {
		t.Errorf("taken adapters should be empty after rollback")
	}
}

func TestCleanAdapterState(t *testing.T) {
	dirty := AdapterState{
		ID:          "{GUID-DIRTY}",
		Name:        "WLAN",
		Index:       7,
		Description: "Wi-Fi",
		IPv4DHCP:    false,
		IPv6DHCP:    false,
		IPv4DNS:     []string{"127.0.0.1"},
		IPv6DNS:     []string{"::1"},
	}

	cleaned := CleanAdapterState(dirty)
	if !cleaned.IPv4DHCP {
		t.Errorf("expected IPv4DHCP to be true after cleaning, got false")
	}
	if !cleaned.IPv6DHCP {
		t.Errorf("expected IPv6DHCP to be true after cleaning, got false")
	}
	if len(cleaned.IPv4DNS) != 0 {
		t.Errorf("expected empty IPv4DNS, got %v", cleaned.IPv4DNS)
	}
	if len(cleaned.IPv6DNS) != 0 {
		t.Errorf("expected empty IPv6DNS, got %v", cleaned.IPv6DNS)
	}

	// 测试真实静态 DNS 保留
	realStatic := AdapterState{
		ID:          "{GUID-REAL}",
		Name:        "以太网",
		Index:       8,
		IPv4DHCP:    false,
		IPv6DHCP:    false,
		IPv4DNS:     []string{"127.0.0.1", "8.8.8.8"},
		IPv6DNS:     []string{"::1", "2001:4860:4860::8888"},
	}
	cleanedStatic := CleanAdapterState(realStatic)
	if cleanedStatic.IPv4DHCP {
		t.Errorf("expected IPv4DHCP to remain false for real static DNS")
	}
	if len(cleanedStatic.IPv4DNS) != 1 || cleanedStatic.IPv4DNS[0] != "8.8.8.8" {
		t.Errorf("unexpected cleaned IPv4DNS: %v", cleanedStatic.IPv4DNS)
	}
	if len(cleanedStatic.IPv6DNS) != 1 || cleanedStatic.IPv6DNS[0] != "2001:4860:4860::8888" {
		t.Errorf("unexpected cleaned IPv6DNS: %v", cleanedStatic.IPv6DNS)
	}
}

func TestGenerateRestoreScript_FilterLoopback(t *testing.T) {
	tmpDir := t.TempDir()
	batPath := filepath.Join(tmpDir, "restore-dns.bat")

	// 模拟此前被误记录为静态 127.0.0.1 的残留网卡快照
	dirtyStates := []AdapterState{
		{
			ID:          "{GUID-DIRTY}",
			Name:        "WLAN",
			Index:       7,
			IPv4DHCP:    false,
			IPv6DHCP:    false,
			IPv4DNS:     []string{"127.0.0.1"},
			IPv6DNS:     []string{"::1"},
		},
	}

	if err := GenerateRestoreScript(dirtyStates, batPath); err != nil {
		t.Fatalf("GenerateRestoreScript failed: %v", err)
	}

	bytes, err := os.ReadFile(batPath)
	if err != nil {
		t.Fatalf("read generated bat failed: %v", err)
	}
	content := string(bytes)

	// 必须生成 source=dhcp 命令，绝对不可生成 static 127.0.0.1
	if !strings.Contains(content, "netsh interface ipv4 set dnsservers name=\"WLAN\" source=dhcp") {
		t.Errorf("bat should contain IPv4 source=dhcp, got: %s", content)
	}
	if !strings.Contains(content, "netsh interface ipv6 set dnsservers name=\"WLAN\" source=dhcp") {
		t.Errorf("bat should contain IPv6 source=dhcp, got: %s", content)
	}
	if strings.Contains(content, "127.0.0.1") {
		t.Errorf("bat must NOT contain 127.0.0.1: %s", content)
	}
	if strings.Contains(content, "::1") {
		t.Errorf("bat must NOT contain ::1: %s", content)
	}
}

func TestRestoreAdapters_FiltersResidualLoopback(t *testing.T) {
	mock := &mockExecutor{}
	store := NewFileStateStore(filepath.Join(t.TempDir(), "dns_state.json"))
	mgr := NewDNSManager(mock, store, "0.1.0-test")

	resetCalled := false
	var setterServers []string
	mgr.dnsResetter = func(guidStr string) error {
		if guidStr == "{GUID-1}" {
			resetCalled = true
		}
		return nil
	}
	mgr.dnsSetter = func(guidStr string, servers []string) error {
		setterServers = append(setterServers, servers...)
		return nil
	}

	// 传入残留 127.0.0.1 与 ::1 的网卡快照
	dirtyAdapters := []AdapterState{
		{
			ID:       "{GUID-1}",
			Name:     "WLAN",
			Index:    7,
			IPv4DHCP: false,
			IPv6DHCP: false,
			IPv4DNS:  []string{"127.0.0.1"},
			IPv6DNS:  []string{"::1"},
		},
	}

	if err := mgr.RestoreAdapters(context.Background(), dirtyAdapters); err != nil {
		t.Fatalf("RestoreAdapters failed: %v", err)
	}

	if !resetCalled {
		t.Errorf("expected native dnsResetter called for {GUID-1}")
	}
	for _, s := range setterServers {
		if strings.Contains(s, "127.0.0.1") {
			t.Errorf("dnsSetter should not be called with 127.0.0.1, got: %s", s)
		}
	}
}

func TestResetResidualLoopbackDNS(t *testing.T) {
	mock := &mockExecutor{}
	store := NewFileStateStore(filepath.Join(t.TempDir(), "dns_state.json"))
	mgr := NewDNSManager(mock, store, "0.1.0-test")

	residualCalled := false
	mgr.residualResetter = func(ctx context.Context) error {
		residualCalled = true
		return nil
	}

	if err := mgr.ResetResidualLoopbackDNS(context.Background()); err != nil {
		t.Fatalf("ResetResidualLoopbackDNS failed: %v", err)
	}

	if !residualCalled {
		t.Fatalf("expected residualResetter called")
	}
}

func TestRestore_CleansResidualEvenWhenNoAdapters(t *testing.T) {
	mock := &mockExecutor{}
	store := NewFileStateStore(filepath.Join(t.TempDir(), "dns_state.json"))
	mgr := NewDNSManager(mock, store, "0.1.0-test")

	residualCalled := false
	mgr.residualResetter = func(ctx context.Context) error {
		residualCalled = true
		return nil
	}

	// 模拟没有任何被接管网卡时调用 Restore
	if err := mgr.Restore(context.Background()); err != nil {
		t.Fatalf("Restore failed: %v", err)
	}

	if !residualCalled {
		t.Errorf("Restore should execute ResetResidualLoopbackDNS sweep even when adapters list was empty")
	}
}

