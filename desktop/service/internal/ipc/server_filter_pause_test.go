package ipc

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIPC_FilterPauseGetEndpoint(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/filter/pause", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterPause(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[*FilterPauseResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if res.Data.Paused {
		t.Fatalf("初始状态不应处于暂停")
	}
}

func TestIPC_FilterPausePostPauseAndResume(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	// 暂停 30 分钟
	body, _ := json.Marshal(FilterPauseRequest{Paused: true, DurationSec: 1800})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/filter/pause", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterPause(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if mockCtrl.filterPause == nil || !mockCtrl.filterPause.Paused {
		t.Fatalf("暂停状态未写入 mock: %+v", mockCtrl.filterPause)
	}
	if mockCtrl.filterPause.RemainingSeconds != 1800 {
		t.Fatalf("剩余秒数应为 1800, 得到 %d", mockCtrl.filterPause.RemainingSeconds)
	}

	// 恢复
	body, _ = json.Marshal(FilterPauseRequest{Paused: false})
	req = httptest.NewRequest(http.MethodPost, "/api/v1/filter/pause", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleFilterPause(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if mockCtrl.filterPause.Paused {
		t.Fatalf("恢复后不应处于暂停: %+v", mockCtrl.filterPause)
	}
}

func TestIPC_FilterPausePostBadJSON(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/filter/pause", bytes.NewReader([]byte("{not json")))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterPause(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestIPC_FilterPauseMethodNotAllowed(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/filter/pause", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterPause(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}
