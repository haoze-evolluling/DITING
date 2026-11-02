package ipc

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/platform"
)

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

	// 测试 Partial Filter Config 更新 (只发送 {"enabled": false}，验证 Lists 和 CustomRules 不被冲刷重置)
	partialFilterBody := strings.NewReader(`{"enabled":false}`)
	var partialFilterResp Response[string]
	if err := client.doRequest(ctx, http.MethodPost, "/api/v1/filter/config", partialFilterBody, &partialFilterResp); err != nil {
		t.Fatalf("Partial UpdateFilterConfig request failed: %v", err)
	}
	if !partialFilterResp.Success {
		t.Fatalf("Partial UpdateFilterConfig returned failure: %s", partialFilterResp.Error)
	}

	afterPartialFCfg, err := client.GetFilterConfig(ctx)
	if err != nil {
		t.Fatalf("GetFilterConfig after partial update failed: %v", err)
	}
	if afterPartialFCfg.Enabled {
		t.Fatalf("预期 filter enabled 为 false，实际仍为 true")
	}
	if afterPartialFCfg.BlockMode != core.BlockModeNullIP || len(afterPartialFCfg.Lists) == 0 {
		t.Fatalf("Partial 过滤更新错误地将其它字段重置: %+v", afterPartialFCfg)
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

func TestServer_DNSStart_PortConflict(t *testing.T) {
	conflictDetail := &platform.PortCheckResult{
		Available: false,
		HasICS:    true,
		Conflicts: []platform.PortConflict{
			{
				Port:         53,
				Protocol:     "UDP",
				LocalAddress: "0.0.0.0:53",
				PID:          1768,
				ProcessName:  "svchost",
				ServiceName:  "SharedAccess",
				IsICS:        true,
				Diagnosis:    "Windows ICS 占用 53 端口",
			},
		},
		Diagnostic: "53 端口被 SharedAccess 占用",
	}

	mockCtrl := &mockController{
		startErr: &platform.PortConflictError{Result: conflictDetail},
	}
	token := "test-secret-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)

	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() {
		_ = server.Shutdown(context.Background())
	}()

	client := NewClient(server.Addr(), token)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	err := client.StartDNS(ctx)
	if err == nil {
		t.Fatalf("expected port conflict error, got nil")
	}

	var pErr *platform.PortConflictError
	if !errors.As(err, &pErr) {
		t.Fatalf("expected errors.As to match *platform.PortConflictError, got: %T (%v)", err, err)
	}
	if pErr.Result == nil || !pErr.Result.HasICS {
		t.Fatalf("expected PortConflictError to contain conflict result with HasICS=true, got %+v", pErr.Result)
	}
}
