package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// sbMockController 覆盖 B6 的声誉查询配置读写
type sbMockController struct {
	mockController
	cfg     *SafeBrowsingResponse
	updated bool
	lastReq ConfigureSafeBrowsingRequest
	fail    bool
}

func (m *sbMockController) GetSafeBrowsing(ctx context.Context) (*SafeBrowsingResponse, error) {
	if m.fail {
		return nil, errSafeBrowsingTestFailure
	}
	if m.cfg != nil {
		return m.cfg, nil
	}
	return &SafeBrowsingResponse{
		Config:    core.DefaultSafeBrowsingConfig(),
		BlockMode: core.BlockModeNullIP,
	}, nil
}

func (m *sbMockController) ConfigureSafeBrowsing(ctx context.Context, req ConfigureSafeBrowsingRequest) error {
	if m.fail {
		return errSafeBrowsingTestFailure
	}
	m.updated = true
	m.lastReq = req
	return nil
}

var errSafeBrowsingTestFailure = errors.New("safe browsing unavailable")

func callSafeBrowsing(t *testing.T, srv *Server, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, "/api/v1/filter/safebrowsing", reader)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	srv.handleSafeBrowsing(w, req)
	return w
}

func TestServer_SafeBrowsingGet(t *testing.T) {
	cfg := core.DefaultSafeBrowsingConfig()
	cfg.Enabled = true
	ctrl := &sbMockController{cfg: &SafeBrowsingResponse{
		Config: cfg,
		Stats:  core.SafeBrowsingStats{Lookups: 3, Blocked: 1, CacheHits: 2},
		// 拦截应答沿用规则拦截的全局策略，前端据此预览形态
		BlockingIPv4: "0.0.0.0",
		BlockingIPv6: "::",
		BlockMode:    core.BlockModeNullIP,
	}}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callSafeBrowsing(t, srv, http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[*SafeBrowsingResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if !res.Data.Config.Enabled {
		t.Fatal("启用状态应回传")
	}
	if res.Data.Stats.Blocked != 1 || res.Data.Stats.CacheHits != 2 {
		t.Fatalf("统计不符: %+v", res.Data.Stats)
	}
	if res.Data.BlockMode != core.BlockModeNullIP {
		t.Fatalf("拦截方式应一并回传，实得 %q", res.Data.BlockMode)
	}
	if ctrl.updated {
		t.Fatal("GET 不应触发配置更新")
	}
}

func TestServer_SafeBrowsingGetError(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &sbMockController{fail: true})

	if w := callSafeBrowsing(t, srv, http.MethodGet, ""); w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
}

func TestServer_SafeBrowsingPost(t *testing.T) {
	ctrl := &sbMockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callSafeBrowsing(t, srv, http.MethodPost, `{"enabled":true,"parentalEnabled":true,"timeoutMs":1500}`)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if !ctrl.updated {
		t.Fatal("POST 应触发配置更新")
	}
	if ctrl.lastReq.Enabled == nil || !*ctrl.lastReq.Enabled {
		t.Fatal("enabled 未透传")
	}
	if ctrl.lastReq.ParentalEnabled == nil || !*ctrl.lastReq.ParentalEnabled {
		t.Fatal("parentalEnabled 未透传")
	}
	if ctrl.lastReq.TimeoutMs == nil || *ctrl.lastReq.TimeoutMs != 1500 {
		t.Fatal("timeoutMs 未透传")
	}
	// 未提交的字段必须保持 nil，否则会把用户没碰过的项改回零值
	if ctrl.lastReq.CacheSize != nil || ctrl.lastReq.CacheTTLSeconds != nil {
		t.Fatal("未提交的字段不应被填充")
	}

	var res Response[*SafeBrowsingResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("POST 应回传更新后的状态: %+v", res)
	}
}

func TestServer_SafeBrowsingPostError(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &sbMockController{fail: true})

	if w := callSafeBrowsing(t, srv, http.MethodPost, `{"enabled":true}`); w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
}

func TestServer_SafeBrowsingPostBadJSON(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &sbMockController{})

	if w := callSafeBrowsing(t, srv, http.MethodPost, `{not json`); w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

func TestServer_SafeBrowsingMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &sbMockController{})

	if w := callSafeBrowsing(t, srv, http.MethodDelete, ""); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}

func TestServer_SafeBrowsingRequiresAuth(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &sbMockController{})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/filter/safebrowsing", nil)
	w := httptest.NewRecorder()

	srv.withAuth(srv.handleSafeBrowsing)(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
}
