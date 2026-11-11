package ipc

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func newCachePersistServer(t *testing.T, mock *mockController) *Server {
	t.Helper()
	return NewServer("127.0.0.1:0", "secret-token", mock)
}

func TestIPC_CachePersistStatus(t *testing.T) {
	mock := &mockController{}
	mock.cachePersist = &CachePersistResponse{
		Path:         "/var/data/dns_cache.json",
		PersistOn:    true,
		EntryCount:   12,
		IntervalSec:  300,
		ExcludeRules: []string{`\.local$`, `^ads\.`},
		ExcludeHits:  7,
	}
	server := newCachePersistServer(t, mock)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/cache/persist", nil)
	w := httptest.NewRecorder()
	server.handleCachePersist(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var res Response[*CachePersistResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if res.Data.Path != "/var/data/dns_cache.json" || !res.Data.PersistOn || res.Data.EntryCount != 12 {
		t.Fatalf("data = %+v", res.Data)
	}
	if len(res.Data.ExcludeRules) != 2 || res.Data.ExcludeHits != 7 {
		t.Fatalf("exclude stats not surfaced: %+v", res.Data)
	}
}

func TestIPC_CachePersistStatus_MethodNotAllowed(t *testing.T) {
	server := newCachePersistServer(t, &mockController{})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/cache/persist", nil)
	w := httptest.NewRecorder()
	server.handleCachePersist(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestIPC_CachePersistStatus_Error(t *testing.T) {
	mock := &mockController{}
	mock.cachePersistErr = true
	server := newCachePersistServer(t, mock)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/cache/persist", nil)
	w := httptest.NewRecorder()
	server.handleCachePersist(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d: %s", w.Code, w.Body.String())
	}
}

func TestIPC_CacheDump(t *testing.T) {
	mock := &mockController{}
	server := newCachePersistServer(t, mock)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/cache/dump", nil)
	w := httptest.NewRecorder()
	server.handleCacheDump(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !mock.cacheDumped {
		t.Fatal("the controller must be asked to dump the cache")
	}
	var res Response[*CachePersistResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil || res.Data.EntryCount != 7 {
		t.Fatalf("unexpected response: %+v", res)
	}
	// 落盘属于可观测的状态变更，必须广播事件让控制台刷新
	if res.Message == "" {
		t.Fatal("a successful dump should carry a message")
	}
}

func TestIPC_CacheDump_MethodNotAllowed(t *testing.T) {
	server := newCachePersistServer(t, &mockController{})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/cache/dump", nil)
	w := httptest.NewRecorder()
	server.handleCacheDump(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestIPC_CacheLoad(t *testing.T) {
	mock := &mockController{}
	server := newCachePersistServer(t, mock)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/cache/load", nil)
	w := httptest.NewRecorder()
	server.handleCacheLoad(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !mock.cacheLoaded {
		t.Fatal("the controller must be asked to load the cache")
	}
	var res Response[*CachePersistResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !res.Success || res.Data == nil || res.Data.Restored != 7 {
		t.Fatalf("unexpected response: %+v", res)
	}
}

func TestIPC_CacheLoad_MethodNotAllowed(t *testing.T) {
	server := newCachePersistServer(t, &mockController{})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/cache/load", nil)
	w := httptest.NewRecorder()
	server.handleCacheLoad(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

// 三条路由都必须经 withAuth 包装：无凭证请求一律被拒
func TestIPC_CachePersist_RoutesRequireAuth(t *testing.T) {
	server := newCachePersistServer(t, &mockController{})
	mux := http.NewServeMux()
	server.registerRoutes(mux)

	cases := []struct {
		method string
		path   string
	}{
		{http.MethodGet, "/api/v1/cache/persist"},
		{http.MethodPost, "/api/v1/cache/dump"},
		{http.MethodPost, "/api/v1/cache/load"},
	}
	for _, c := range cases {
		req := httptest.NewRequest(c.method, c.path, nil)
		req.RemoteAddr = "203.0.113.7:12345"
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, req)

		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s %s: expected 401, got %d: %s", c.method, c.path, w.Code, w.Body.String())
		}
	}
}

// 携带正确凭证时应放行到处理器
func TestIPC_CachePersist_RoutesAcceptToken(t *testing.T) {
	mock := &mockController{}
	server := newCachePersistServer(t, mock)
	mux := http.NewServeMux()
	server.registerRoutes(mux)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/cache/persist", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}
