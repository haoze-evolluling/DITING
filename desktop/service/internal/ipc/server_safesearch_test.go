package ipc

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIPC_SafeSearchGetEndpoint(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/safesearch/config", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleSafeSearch(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[*SafeSearchConfigResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if res.Data.Enabled {
		t.Fatalf("默认应关闭")
	}
}

func TestIPC_SafeSearchConfigure(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	enabled := true
	disabled := []string{"google", "invalid-service", "google"}
	ttl := uint32(600)
	body, _ := json.Marshal(ConfigureSafeSearchRequest{Enabled: &enabled, Disabled: &disabled, TTL: &ttl})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/safesearch/config", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleSafeSearch(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if mockCtrl.safeSearch == nil || !mockCtrl.safeSearch.Enabled {
		t.Fatalf("配置未生效: %+v", mockCtrl.safeSearch)
	}
	// 非法项被过滤且去重
	if len(mockCtrl.safeSearch.Disabled) != 1 || mockCtrl.safeSearch.Disabled[0] != "google" {
		t.Fatalf("disabled 列表清洗异常: %+v", mockCtrl.safeSearch.Disabled)
	}
	if mockCtrl.safeSearch.TTL != 600 {
		t.Fatalf("TTL 未更新: %d", mockCtrl.safeSearch.TTL)
	}
}

func TestIPC_SafeSearchBadJSON(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/safesearch/config", bytes.NewReader([]byte("{bad")))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleSafeSearch(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestIPC_SafeSearchMethodNotAllowed(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/safesearch/config", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleSafeSearch(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestNormalizeSafeSearchDisabled(t *testing.T) {
	got := normalizeSafeSearchDisabled([]string{"google", "nope", "google", "yandex"})
	if len(got) != 2 || got[0] != "google" || got[1] != "yandex" {
		t.Fatalf("清洗结果异常: %+v", got)
	}
}
