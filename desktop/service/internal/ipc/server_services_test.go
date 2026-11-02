package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// servicesMockController 覆盖 B3 的目录与勾选读写
type servicesMockController struct {
	mockController
	services []core.BlockedService
	groups   []core.BlockedServiceGroup
	ids      []string
	grps     []string
	updated  bool
	fail     bool
}

func (m *servicesMockController) GetBlockedServices(ctx context.Context) (*BlockedServicesResponse, error) {
	if m.fail {
		return nil, errBlockedServicesTestFailure
	}
	return &BlockedServicesResponse{
		Services:      m.services,
		Groups:        m.groups,
		BlockedIDs:    m.ids,
		BlockedGroups: m.grps,
		ActiveRules:   len(m.services),
	}, nil
}

func (m *servicesMockController) ConfigureBlockedServices(ctx context.Context, req ConfigureBlockedServicesRequest) error {
	if m.fail {
		return errBlockedServicesTestFailure
	}
	m.updated = true
	if req.IDs != nil {
		m.ids = *req.IDs
	}
	if req.Groups != nil {
		m.grps = *req.Groups
	}
	return nil
}

var errBlockedServicesTestFailure = errors.New("blocked services unavailable")

func newServicesServer(ctrl *servicesMockController) *Server {
	return NewServer("127.0.0.1:0", "secret-token", ctrl)
}

func callServices(t *testing.T, srv *Server, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, "/api/v1/filter/services", reader)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	srv.handleBlockedServices(w, req)
	return w
}

func TestServer_BlockedServicesGet(t *testing.T) {
	ctrl := &servicesMockController{
		services: []core.BlockedService{
			{ID: "bilibili", Name: "Bilibili", Group: "streaming", RuleN: 2, Source: "service:bilibili"},
		},
		groups: []core.BlockedServiceGroup{{ID: "streaming", Name: "流媒体", Count: 1}},
		ids:    []string{"bilibili"},
	}
	srv := newServicesServer(ctrl)

	w := callServices(t, srv, http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[*BlockedServicesResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if len(res.Data.Services) != 1 || res.Data.Services[0].ID != "bilibili" {
		t.Fatalf("服务清单不符: %+v", res.Data.Services)
	}
	if len(res.Data.Groups) != 1 || res.Data.Groups[0].Name != "流媒体" {
		t.Fatalf("分组清单不符: %+v", res.Data.Groups)
	}
	if ctrl.updated {
		t.Fatal("GET 不应触发配置更新")
	}
}

func TestServer_BlockedServicesGetError(t *testing.T) {
	srv := newServicesServer(&servicesMockController{fail: true})

	if w := callServices(t, srv, http.MethodGet, ""); w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
}

func TestServer_BlockedServicesPost(t *testing.T) {
	ctrl := &servicesMockController{
		services: []core.BlockedService{{ID: "zhihu", Name: "知乎", Group: "social_network", RuleN: 3}},
		groups:   []core.BlockedServiceGroup{{ID: "short_video", Name: "短视频", Count: 2}},
	}
	srv := newServicesServer(ctrl)

	w := callServices(t, srv, http.MethodPost, `{"ids":["zhihu"],"groups":["short_video"]}`)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if !ctrl.updated {
		t.Fatal("POST 应触发配置更新")
	}
	if len(ctrl.ids) != 1 || ctrl.ids[0] != "zhihu" {
		t.Fatalf("ids 未正确写入: %+v", ctrl.ids)
	}
	if len(ctrl.grps) != 1 || ctrl.grps[0] != "short_video" {
		t.Fatalf("groups 未正确写入: %+v", ctrl.grps)
	}

	// 回传更新后的状态，前端无需再发一次 GET
	var res Response[*BlockedServicesResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if res.Data == nil || len(res.Data.BlockedIDs) != 1 || res.Data.BlockedIDs[0] != "zhihu" {
		t.Fatalf("响应未回传更新后状态: %+v", res.Data)
	}
}

// 只传 groups 时 ids 必须保持未设置，否则会把用户的服务勾选一并清空
func TestServer_BlockedServicesPostPartial(t *testing.T) {
	ctrl := &servicesMockController{ids: []string{"bilibili"}}
	srv := newServicesServer(ctrl)

	if w := callServices(t, srv, http.MethodPost, `{"groups":[]}`); w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if len(ctrl.ids) != 1 || ctrl.ids[0] != "bilibili" {
		t.Fatalf("未传 ids 时不应被改动: %+v", ctrl.ids)
	}
	if ctrl.grps == nil || len(ctrl.grps) != 0 {
		t.Fatalf("空数组应被识别为「清空分组」: %+v", ctrl.grps)
	}
}

func TestServer_BlockedServicesPostBadJSON(t *testing.T) {
	ctrl := &servicesMockController{}
	srv := newServicesServer(ctrl)

	w := callServices(t, srv, http.MethodPost, "{not json")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
	if ctrl.updated {
		t.Fatal("非法 JSON 不应触发配置更新")
	}
	if !strings.Contains(w.Body.String(), "解析请求 JSON 失败") {
		t.Fatalf("错误信息不明确: %s", w.Body.String())
	}
}

func TestServer_BlockedServicesMethodNotAllowed(t *testing.T) {
	srv := newServicesServer(&servicesMockController{})

	if w := callServices(t, srv, http.MethodDelete, ""); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}
