package ipc

import (
	"context"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

type mockController struct {
	mu           sync.Mutex
	dnsRunning   bool
	takeoverOn   bool
	startErr     error
	stopErr      error
	takeoverErr  error
	restoreErr   error
	statusResult *StatusResponse
	portResult   *windows.PortCheckResult
	cacheConfig  *core.CacheConfig
}

func (m *mockController) StartDNS(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.startErr != nil {
		return m.startErr
	}
	m.dnsRunning = true
	return nil
}

func (m *mockController) StopDNS(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.stopErr != nil {
		return m.stopErr
	}
	m.dnsRunning = false
	return nil
}

func (m *mockController) EnableTakeover(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.takeoverErr != nil {
		return m.takeoverErr
	}
	m.takeoverOn = true
	return nil
}

func (m *mockController) DisableTakeover(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.restoreErr != nil {
		return m.restoreErr
	}
	m.takeoverOn = false
	return nil
}

func (m *mockController) GetStatus(ctx context.Context) (*StatusResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.statusResult != nil {
		return m.statusResult, nil
	}
	return &StatusResponse{
		Version:       "0.1.0-test",
		PID:           1000,
		UptimeSeconds: 120,
		DNS: DNSStatus{
			Running:         m.dnsRunning,
			ListenAddresses: []string{"127.0.0.1:53"},
			Mode:            "PRIMARY_BACKUP",
		},
		Takeover: TakeoverStatus{
			Active: m.takeoverOn,
		},
		Metrics: MetricsStatus{
			TotalQueries: 42,
		},
	}, nil
}

func (m *mockController) CheckPortConflicts(ctx context.Context) (*windows.PortCheckResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.portResult != nil {
		return m.portResult, nil
	}
	return &windows.PortCheckResult{
		Available:  true,
		Conflicts:  []windows.PortConflict{},
		HasICS:     false,
		Diagnostic: "53 端口空闲且可用",
	}, nil
}

func (m *mockController) GetAdapters(ctx context.Context) ([]windows.AdapterInfo, error) {
	return []windows.AdapterInfo{
		{
			ID:         "{GUID-TEST}",
			Name:       "WLAN",
			Index:      8,
			Status:     "Up",
			Gateway:    "192.168.1.1",
			IsPhysical: true,
		},
	}, nil
}

func (m *mockController) ConfigureUpstream(ctx context.Context, req ConfigureUpstreamRequest) error {
	return nil
}

func (m *mockController) TestUpstream(ctx context.Context, req TestUpstreamRequest) (*TestUpstreamResponse, error) {
	return &TestUpstreamResponse{Success: true, LatencyMs: 12.5}, nil
}

func (m *mockController) SetAdapterTakeover(ctx context.Context, req AdapterTakeoverRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.takeoverOn = req.Enable
	return nil
}

func (m *mockController) GetCacheStats(ctx context.Context) (*core.CacheStats, error) {
	return &core.CacheStats{
		Enabled:     true,
		TotalHits:   10,
		TotalMisses: 2,
		HitRatio:    0.833,
		EntryCount:  5,
		MaxEntries:  4096,
	}, nil
}

func (m *mockController) GetCacheEntries(ctx context.Context, query string, limit int) (*CacheEntriesResponse, error) {
	return &CacheEntriesResponse{
		Total: 1,
		Entries: []core.CacheEntryItem{
			{
				Domain:       "test.com",
				QType:        "A",
				TTL:          60,
				RemainingTTL: 55,
				HitCount:     10,
				Status:       "fresh",
			},
		},
	}, nil
}

func (m *mockController) GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error) {
	return []core.CacheDomainStat{
		{Domain: "test.com", QType: "A", HitCount: 10},
	}, nil
}

func (m *mockController) ClearCache(ctx context.Context) error {
	return nil
}

func (m *mockController) GetCacheConfig(ctx context.Context) (*core.CacheConfig, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cacheConfig != nil {
		cpy := *m.cacheConfig
		return &cpy, nil
	}
	cfg := core.DefaultCacheConfig()
	return &cfg, nil
}

func (m *mockController) UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cacheConfig = &cfg
	return nil
}

func (m *mockController) GetFilterStats(ctx context.Context) (*core.FilterStats, error) {
	return &core.FilterStats{Enabled: true, TotalRules: 100, ActiveLists: 1, BlockedQueries: 5, BlockRate: 5.0}, nil
}

func (m *mockController) GetFilterConfig(ctx context.Context) (*core.FilterConfig, error) {
	cfg := core.DefaultFilterConfig()
	return &cfg, nil
}

func (m *mockController) UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error {
	return nil
}

func (m *mockController) GetFilterLists(ctx context.Context) ([]core.FilterList, error) {
	return []core.FilterList{{ID: "test-list", Name: "Test List", Enabled: true, RulesCount: 10}}, nil
}

func (m *mockController) AddFilterList(ctx context.Context, list core.FilterList) error {
	return nil
}

func (m *mockController) UpdateFilterList(ctx context.Context, list core.FilterList) error {
	return nil
}

func (m *mockController) DeleteFilterList(ctx context.Context, id string) error {
	return nil
}

func (m *mockController) RefreshFilterLists(ctx context.Context, id string) error {
	return nil
}

func (m *mockController) GetCustomRules(ctx context.Context) ([]string, error) {
	return []string{"||ad.com^"}, nil
}

func (m *mockController) SetCustomRules(ctx context.Context, rules []string) error {
	return nil
}

func (m *mockController) CheckHostRule(ctx context.Context, domain string, qtype uint16) (*core.CheckHostResult, error) {
	return &core.CheckHostResult{Blocked: true, Action: "block", MatchedRule: "||ad.com^", Reason: "blacklist"}, nil
}

func TestIPCServerAndClient_EndToEnd(t *testing.T) {
	mockCtrl := &mockController{}
	token := "test-secret-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)

	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() {
		_ = server.Shutdown(context.Background())
	}()

	addr := server.Addr()
	client := NewClient(addr, token)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// 1. 测试 HealthCheck
	if err := client.HealthCheck(ctx); err != nil {
		t.Fatalf("HealthCheck failed: %v", err)
	}

	// 2. 测试鉴权失败
	unauthClient := NewClient(addr, "wrong-token")
	if err := unauthClient.StartDNS(ctx); err == nil {
		t.Fatalf("expected unauth error, got nil")
	}

	// 3. 测试 StartDNS & StopDNS
	if err := client.StartDNS(ctx); err != nil {
		t.Fatalf("StartDNS failed: %v", err)
	}
	status, err := client.GetStatus(ctx)
	if err != nil || !status.DNS.Running {
		t.Fatalf("expected DNS running, got err=%v, status=%+v", err, status)
	}

	if err := client.StopDNS(ctx); err != nil {
		t.Fatalf("StopDNS failed: %v", err)
	}
	status, err = client.GetStatus(ctx)
	if err != nil || status.DNS.Running {
		t.Fatalf("expected DNS stopped, got err=%v, status=%+v", err, status)
	}

	// 4. 测试 EnableTakeover & DisableTakeover
	if err := client.EnableTakeover(ctx); err != nil {
		t.Fatalf("EnableTakeover failed: %v", err)
	}
	status, err = client.GetStatus(ctx)
	if err != nil || !status.Takeover.Active {
		t.Fatalf("expected Takeover active, got err=%v, status=%+v", err, status)
	}

	if err := client.DisableTakeover(ctx); err != nil {
		t.Fatalf("DisableTakeover failed: %v", err)
	}
	status, err = client.GetStatus(ctx)
	if err != nil || status.Takeover.Active {
		t.Fatalf("expected Takeover inactive, got err=%v, status=%+v", err, status)
	}

	// 5. 测试 CheckPortConflicts
	portRes, err := client.CheckPortConflicts(ctx)
	if err != nil || !portRes.Available {
		t.Fatalf("CheckPortConflicts failed: err=%v, portRes=%+v", err, portRes)
	}

	// 6. 测试 GetAdapters
	adapters, err := client.GetAdapters(ctx)
	if err != nil || len(adapters) != 1 || adapters[0].Name != "WLAN" {
		t.Fatalf("GetAdapters failed: err=%v, adapters=%+v", err, adapters)
	}

	// 7. 测试 WebSocket 事件订阅
	eventsCh, unsub, err := client.SubscribeEvents(ctx)
	if err != nil {
		t.Fatalf("SubscribeEvents failed: %v", err)
	}
	defer unsub()

	// 等待连接注册完成
	time.Sleep(100 * time.Millisecond)

	// 广播事件
	testEvt := Event{
		Type:      "query",
		Timestamp: time.Now().UnixMilli(),
		Data: QueryEventData{
			Domain:     "example.com.",
			QType:      "A",
			ClientIP:   "127.0.0.1",
			DurationMs: 12.5,
			Success:    true,
		},
	}
	server.Broadcast(testEvt)

	// 验证客户端是否收到
	select {
	case received := <-eventsCh:
		if received.Type != "query" {
			t.Fatalf("expected event type query, got %s", received.Type)
		}
	case <-time.After(3 * time.Second):
		t.Fatalf("timeout waiting for WebSocket event")
	}

	// 8. 测试 ConfigureUpstream, TestUpstream, SetAdapterTakeover
	if err := client.ConfigureUpstream(ctx, ConfigureUpstreamRequest{Mode: "SINGLE"}); err != nil {
		t.Fatalf("ConfigureUpstream failed: %v", err)
	}

	testRes, err := client.TestUpstream(ctx, TestUpstreamRequest{Protocol: "PLAIN", Server: "223.5.5.5:53"})
	if err != nil || !testRes.Success {
		t.Fatalf("TestUpstream failed: err=%v, res=%+v", err, testRes)
	}

	if err := client.SetAdapterTakeover(ctx, AdapterTakeoverRequest{AdapterID: "{GUID-TEST}", Enable: true}); err != nil {
		t.Fatalf("SetAdapterTakeover failed: %v", err)
	}

	// 9. 测试智能缓存 (Phase 5) API: Stats, Entries, Top, Clear, Config
	cStats, err := client.GetCacheStats(ctx)
	if err != nil || !cStats.Enabled {
		t.Fatalf("GetCacheStats failed: err=%v, stats=%+v", err, cStats)
	}

	cEntries, err := client.GetCacheEntries(ctx, "test", 10)
	if err != nil || cEntries.Total != 1 {
		t.Fatalf("GetCacheEntries failed: err=%v, res=%+v", err, cEntries)
	}

	cTop, err := client.GetCacheTopDomains(ctx, 5)
	if err != nil || len(cTop) != 1 {
		t.Fatalf("GetCacheTopDomains failed: err=%v, top=%+v", err, cTop)
	}

	if err := client.ClearCache(ctx); err != nil {
		t.Fatalf("ClearCache failed: %v", err)
	}

	cCfg, err := client.GetCacheConfig(ctx)
	if err != nil || !cCfg.Enabled {
		t.Fatalf("GetCacheConfig failed: err=%v, cfg=%+v", err, cCfg)
	}

	if err := client.UpdateCacheConfig(ctx, *cCfg); err != nil {
		t.Fatalf("UpdateCacheConfig failed: %v", err)
	}

	// 10. 测试 Partial Config 更新 (只发送 {"enabled": false}，验证其余布尔项与数值不被冲刷成零值)
	partialBody := strings.NewReader(`{"enabled":false}`)
	var partialResp Response[string]
	if err := client.doRequest(ctx, http.MethodPost, "/api/v1/cache/config", partialBody, &partialResp); err != nil {
		t.Fatalf("Partial UpdateCacheConfig request failed: %v", err)
	}
	if !partialResp.Success {
		t.Fatalf("Partial UpdateCacheConfig returned failure: %s", partialResp.Error)
	}

	afterPartialCfg, err := client.GetCacheConfig(ctx)
	if err != nil {
		t.Fatalf("GetCacheConfig after partial update failed: %v", err)
	}
	if afterPartialCfg.Enabled {
		t.Fatalf("预期 enabled 为 false，实际仍为 true")
	}
	if !afterPartialCfg.Optimistic || !afterPartialCfg.StaleFallbackEnabled || afterPartialCfg.MaxTTLSeconds != 3600 {
		t.Fatalf("Partial 更新错误地将其它字段重置为零值: %+v", afterPartialCfg)
	}

	// 11. 测试规则过滤引擎 (Phase 6) API: Stats, Config, Lists, Rules, Check
	fStats, err := client.GetFilterStats(ctx)
	if err != nil || !fStats.Enabled || fStats.TotalRules != 100 {
		t.Fatalf("GetFilterStats failed: err=%v, stats=%+v", err, fStats)
	}

	fCfg, err := client.GetFilterConfig(ctx)
	if err != nil || !fCfg.Enabled {
		t.Fatalf("GetFilterConfig failed: err=%v, cfg=%+v", err, fCfg)
	}

	if err := client.UpdateFilterConfig(ctx, *fCfg); err != nil {
		t.Fatalf("UpdateFilterConfig failed: %v", err)
	}

	fLists, err := client.GetFilterLists(ctx)
	if err != nil || len(fLists) != 1 {
		t.Fatalf("GetFilterLists failed: err=%v, lists=%+v", err, fLists)
	}

	if err := client.AddFilterList(ctx, core.FilterList{ID: "new-list", Name: "New List", URL: "https://example.com/filter.txt"}); err != nil {
		t.Fatalf("AddFilterList failed: %v", err)
	}

	if err := client.UpdateFilterList(ctx, core.FilterList{ID: "test-list", Name: "Updated List", URL: "https://example.com/updated.txt"}); err != nil {
		t.Fatalf("UpdateFilterList failed: %v", err)
	}

	if err := client.RefreshFilterLists(ctx, "test-list"); err != nil {
		t.Fatalf("RefreshFilterLists failed: %v", err)
	}

	if err := client.DeleteFilterList(ctx, "test-list"); err != nil {
		t.Fatalf("DeleteFilterList failed: %v", err)
	}

	fRules, err := client.GetCustomRules(ctx)
	if err != nil || len(fRules) != 1 {
		t.Fatalf("GetCustomRules failed: err=%v, rules=%+v", err, fRules)
	}

	if err := client.SetCustomRules(ctx, []string{"||ad.example.com^"}); err != nil {
		t.Fatalf("SetCustomRules failed: %v", err)
	}

	checkRes, err := client.CheckHost(ctx, "ad.com", "A")
	if err != nil || !checkRes.Blocked {
		t.Fatalf("CheckHost failed: err=%v, res=%+v", err, checkRes)
	}
}
