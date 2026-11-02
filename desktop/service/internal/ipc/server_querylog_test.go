package ipc

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

func TestIPC_QueryLogSearchEndpoint(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/querylog/search?domain=example.com&limit=10&offset=0", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleQueryLogSearch(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[*querylog.SearchResult]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil || res.Data.Total != 1 || len(res.Data.Entries) != 1 {
		t.Fatalf("unexpected search response: %+v", res)
	}
	if res.Data.Entries[0].Domain != "example.com" {
		t.Fatalf("unexpected entry: %+v", res.Data.Entries[0])
	}
}

func TestIPC_QueryLogSearchParseQuery(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/querylog/search?domain=a.com&client=192.168.1.5&qtype=AAAA&rcode=NXDOMAIN&status=blocked&startMs=1000&endMs=2000&limit=50&offset=5", nil)
	sq := parseSearchQuery(req)

	if sq.Domain != "a.com" || sq.Client != "192.168.1.5" || sq.QType != "AAAA" ||
		sq.RCode != "NXDOMAIN" || sq.Status != "blocked" {
		t.Fatalf("unexpected filters: %+v", sq)
	}
	if sq.StartMs != 1000 || sq.EndMs != 2000 || sq.Limit != 50 || sq.Offset != 5 {
		t.Fatalf("unexpected pagination/time: %+v", sq)
	}
	if !sq.IncludeFile {
		t.Fatalf("expected includeFile default true")
	}

	// 显式关闭落盘回退
	req2 := httptest.NewRequest(http.MethodGet, "/api/v1/querylog/search?includeFile=false", nil)
	if parseSearchQuery(req2).IncludeFile {
		t.Fatalf("expected includeFile false when explicitly disabled")
	}
}

func TestIPC_QueryLogSearchMethodNotAllowed(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/querylog/search", nil)
	w := httptest.NewRecorder()
	server.handleQueryLogSearch(w, req)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestIPC_QueryLogStatsEndpoint(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/querylog/stats", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleQueryLogStats(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[*QueryStatsResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected stats response: %+v", res)
	}
	if res.Data.Summary.Queries != 100 || len(res.Data.TopDomains) != 1 {
		t.Fatalf("unexpected stats payload: %+v", res.Data)
	}
}

func TestIPC_QueryLogClearEndpoint(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	// 非 POST 拒绝
	req := httptest.NewRequest(http.MethodGet, "/api/v1/querylog/clear", nil)
	w := httptest.NewRecorder()
	server.handleQueryLogClear(w, req)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/querylog/clear", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleQueryLogClear(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !mockCtrl.queryLogCleared {
		t.Fatalf("expected ClearQueryLog to be called")
	}
}

func TestIPC_QueryLogConfigEndpoint(t *testing.T) {
	mockCtrl := &mockController{}
	server := NewServer("127.0.0.1:0", "secret-token", mockCtrl)

	// GET 默认配置
	req := httptest.NewRequest(http.MethodGet, "/api/v1/querylog/config", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	server.handleQueryLogConfig(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var getRes Response[*querylog.QueryLogConfig]
	if err := json.Unmarshal(w.Body.Bytes(), &getRes); err != nil || getRes.Data == nil {
		t.Fatalf("unexpected config response: %v", err)
	}
	if !getRes.Data.Enabled || getRes.Data.MaxEntries != querylog.DefaultMaxEntries {
		t.Fatalf("unexpected default config: %+v", getRes.Data)
	}

	// POST 局部更新（合并语义）
	body := []byte(`{"enabled":false,"maxEntries":512}`)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/querylog/config", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleQueryLogConfig(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if mockCtrl.queryLogConfig == nil || mockCtrl.queryLogConfig.Enabled || mockCtrl.queryLogConfig.MaxEntries != 512 {
		t.Fatalf("unexpected updated config: %+v", mockCtrl.queryLogConfig)
	}
	// 未提交字段保持既有值
	if mockCtrl.queryLogConfig.RetentionDays != querylog.DefaultRetentionDays {
		t.Fatalf("expected retention preserved, got %d", mockCtrl.queryLogConfig.RetentionDays)
	}

	// 非法 JSON → 400
	req = httptest.NewRequest(http.MethodPost, "/api/v1/querylog/config", bytes.NewReader([]byte("{bad")))
	req.Header.Set("Authorization", "Bearer secret-token")
	w = httptest.NewRecorder()
	server.handleQueryLogConfig(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}

	// 其他方法 → 405
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/querylog/config", nil)
	w = httptest.NewRecorder()
	server.handleQueryLogConfig(w, req)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}
