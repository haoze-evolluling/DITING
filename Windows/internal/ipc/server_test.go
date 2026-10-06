package ipc

import (
	"context"
	"sync"
	"testing"
	"time"

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

	// 6. 测试 WebSocket 事件订阅
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
}
