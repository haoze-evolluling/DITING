package ipc

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// TestServiceStatusEndpoint 校验宿主机服务状态端点返回真实状态与自启托管信息。
//
// Web 控制台无法直接访问桌面端进程，此端点是其唯一权威数据源，
// 必须完整回传可执行路径与自启机制，避免前端退化为占位文案。
func TestServiceStatusEndpoint(t *testing.T) {
	mockCtrl := &mockController{
		serviceStatus: &platform.CoreServiceStatus{
			Installed:      true,
			Running:        true,
			State:          "running",
			StateText:      "运行中",
			ExecutablePath: `C:\Program Files\DITING\diting-service.exe`,
			CanInstall:     true,
			AutoStart: &platform.AutoStartStatus{
				Enabled:   true,
				Mechanism: platform.AutoStartMechanismService,
				Detail:    "已注册为 Windows 系统服务并设为自动启动，开机无需登录即可守护运行。",
			},
		},
	}

	token := "service-status-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	client := NewClient(server.Addr(), token)

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet,
		client.baseURL+"/api/v1/service/status", nil)
	if err != nil {
		t.Fatalf("build request failed: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET /api/v1/service/status failed: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var payload Response[*platform.CoreServiceStatus]
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatalf("decode service status failed: %v", err)
	}
	if !payload.Success || payload.Data == nil {
		t.Fatalf("expected success with data, got %+v", payload)
	}
	if !payload.Data.Installed || !payload.Data.Running {
		t.Errorf("expected installed running service, got %+v", payload.Data)
	}
	if payload.Data.ExecutablePath == "" {
		t.Error("expected executablePath to be reported, got empty")
	}
	if payload.Data.AutoStart == nil || !payload.Data.AutoStart.Enabled {
		t.Errorf("expected enabled autostart, got %+v", payload.Data.AutoStart)
	}
	if payload.Data.AutoStart.Mechanism != platform.AutoStartMechanismService {
		t.Errorf("expected service autostart mechanism, got %q", payload.Data.AutoStart.Mechanism)
	}
}

// TestServiceStatusEndpointRequiresAuth 校验该端点未被纳入免鉴权白名单。
func TestServiceStatusEndpointRequiresAuth(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	resp, err := http.Get("http://" + server.Addr() + "/api/v1/service/status")
	if err != nil {
		t.Fatalf("GET /api/v1/service/status failed: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 without token, got %d", resp.StatusCode)
	}
}

// TestServiceStatusEndpointMethodNotAllowed 校验非 GET 方法被拒绝。
func TestServiceStatusEndpointMethodNotAllowed(t *testing.T) {
	token := "service-method-token"
	server := NewServer("127.0.0.1:0", token, &mockController{})
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost,
		"http://"+server.Addr()+"/api/v1/service/status", nil)
	if err != nil {
		t.Fatalf("build request failed: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /api/v1/service/status failed: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", resp.StatusCode)
	}
}
