package ipc

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

func TestIPC_ScheduleGetEndpoint(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/filter/schedule", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterSchedule(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[*ScheduleConfigResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if res.Data.Enabled {
		t.Fatalf("默认计划开关应为关闭")
	}
}

func TestIPC_SchedulePostEndpoint(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	enabled := true
	body, _ := json.Marshal(ConfigureScheduleRequest{
		Enabled: &enabled,
		Schedules: &[]core.BlockingSchedule{
			{ID: "night", Name: "夜间", Enabled: true, Start: "23:00", End: "07:00"},
		},
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/filter/schedule", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterSchedule(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[string]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success {
		t.Fatalf("expected success, got %+v", res)
	}
	if mockCtrl.scheduleConfig == nil || !mockCtrl.scheduleConfig.Enabled {
		t.Fatalf("配置未写入 mock: %+v", mockCtrl.scheduleConfig)
	}
	if len(mockCtrl.scheduleConfig.Schedules) != 1 {
		t.Fatalf("计划条目未写入 mock: %+v", mockCtrl.scheduleConfig.Schedules)
	}
}

func TestIPC_SchedulePostBadJSON(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/filter/schedule", bytes.NewReader([]byte("{not json")))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterSchedule(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestIPC_ScheduleMethodNotAllowed(t *testing.T) {
	server := NewServer("127.0.0.1:0", "secret-token", &mockController{})

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/filter/schedule", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleFilterSchedule(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}
