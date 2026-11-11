package ipc

import (
	"context"
	"encoding/json"
	"net/http"
	"runtime"
	"testing"
	"time"
)

// TestMetaEndpoint 校验免鉴权的平台元信息端点返回宿主机 GOOS。
func TestMetaEndpoint(t *testing.T) {
	server := NewServer("127.0.0.1:0", "test-secret-token", &mockController{})
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() {
		_ = server.Shutdown(context.Background())
	}()

	url := "http://" + server.Addr() + "/api/v1/meta"

	// 不带任何 Token 也应可访问（登录前平台自适应需要）。
	resp, err := http.Get(url)
	if err != nil {
		t.Fatalf("GET /api/v1/meta failed: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var payload Response[MetaResponse]
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatalf("decode meta response failed: %v", err)
	}
	if !payload.Success {
		t.Fatalf("expected success=true, got %+v", payload)
	}
	if payload.Data.OS != runtime.GOOS {
		t.Fatalf("expected os=%q, got %q", runtime.GOOS, payload.Data.OS)
	}
}

// TestMetaEndpointMethodNotAllowed 校验非 GET 方法被拒绝。
func TestMetaEndpointMethodNotAllowed(t *testing.T) {
	server := NewServer("127.0.0.1:0", "test-secret-token", &mockController{})
	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() {
		_ = server.Shutdown(context.Background())
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"http://"+server.Addr()+"/api/v1/meta", nil)
	if err != nil {
		t.Fatalf("build request failed: %v", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /api/v1/meta failed: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", resp.StatusCode)
	}
}
