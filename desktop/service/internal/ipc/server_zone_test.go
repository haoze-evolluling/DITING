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

// zoneMockController 覆盖 B5 的区配置读写
type zoneMockController struct {
	mockController
	cfg     *ZoneConfigResponse
	updated bool
	lastReq ConfigureZoneRequest
	fail    bool
}

func (m *zoneMockController) GetZoneConfig(ctx context.Context) (*ZoneConfigResponse, error) {
	if m.fail {
		return nil, errZoneTestFailure
	}
	if m.cfg != nil {
		return m.cfg, nil
	}
	return &ZoneConfigResponse{
		Zones:      []core.ZoneEntry{},
		States:     []core.ZoneState{},
		MaxZones:   core.MaxZoneCount,
		MaxRecords: core.MaxZoneRecords,
	}, nil
}

func (m *zoneMockController) ConfigureZone(ctx context.Context, req ConfigureZoneRequest) error {
	if m.fail {
		return errZoneTestFailure
	}
	m.updated = true
	m.lastReq = req
	return nil
}

var errZoneTestFailure = errors.New("zone unavailable")

func callZone(t *testing.T, srv *Server, path, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	if strings.HasSuffix(path, "/test") {
		srv.handleZoneTest(w, req)
	} else {
		srv.handleZoneConfig(w, req)
	}
	return w
}

func TestServer_ZoneConfigGet(t *testing.T) {
	ctrl := &zoneMockController{cfg: &ZoneConfigResponse{
		Enabled: true,
		TTL:     300,
		Zones: []core.ZoneEntry{{
			ID: "z1", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n",
		}},
		States:      []core.ZoneState{{ID: "z1", Origin: "lan", Records: 1, Loaded: true}},
		RecordCount: 1,
	}}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callZone(t, srv, "/api/v1/dns/zone/config", http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[*ZoneConfigResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("unexpected response: %+v", res)
	}
	if len(res.Data.Zones) != 1 || res.Data.Zones[0].Origin != "lan" {
		t.Fatalf("区清单不符: %+v", res.Data.Zones)
	}
	if !res.Data.States[0].Loaded {
		t.Fatalf("区状态不符: %+v", res.Data.States)
	}
	if ctrl.updated {
		t.Fatal("GET 不应触发配置更新")
	}
}

func TestServer_ZoneConfigGetError(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &zoneMockController{fail: true})

	if w := callZone(t, srv, "/api/v1/dns/zone/config", http.MethodGet, ""); w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", w.Code)
	}
}

func TestServer_ZoneConfigPost(t *testing.T) {
	ctrl := &zoneMockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callZone(t, srv, "/api/v1/dns/zone/config", http.MethodPost,
		`{"enabled":true,"ttl":120,"zones":[{"id":"z1","origin":"lan","content":"www IN A 10.0.0.1\n","enabled":true}]}`)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if !ctrl.updated {
		t.Fatal("POST 应触发配置更新")
	}
	if ctrl.lastReq.Enabled == nil || !*ctrl.lastReq.Enabled {
		t.Fatalf("enabled 未正确写入: %+v", ctrl.lastReq.Enabled)
	}
	if ctrl.lastReq.TTL == nil || *ctrl.lastReq.TTL != 120 {
		t.Fatalf("ttl 未正确写入: %+v", ctrl.lastReq.TTL)
	}
	if ctrl.lastReq.Zones == nil || len(*ctrl.lastReq.Zones) != 1 {
		t.Fatalf("zones 未正确写入: %+v", ctrl.lastReq.Zones)
	}
}

// 只改开关时必须保持 zones 未设置，否则会把用户已写的区一并清空
func TestServer_ZoneConfigPostPartial(t *testing.T) {
	ctrl := &zoneMockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	if w := callZone(t, srv, "/api/v1/dns/zone/config", http.MethodPost, `{"enabled":false}`); w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if ctrl.lastReq.Zones != nil {
		t.Fatalf("未传 zones 时不应被改动: %+v", ctrl.lastReq.Zones)
	}
	if ctrl.lastReq.TTL != nil {
		t.Fatalf("未传 ttl 时不应被改动: %+v", ctrl.lastReq.TTL)
	}
}

func TestServer_ZoneConfigPostBadJSON(t *testing.T) {
	ctrl := &zoneMockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callZone(t, srv, "/api/v1/dns/zone/config", http.MethodPost, "{not json")
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

func TestServer_ZoneConfigMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &zoneMockController{})

	if w := callZone(t, srv, "/api/v1/dns/zone/config", http.MethodDelete, ""); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}

func TestServer_ZoneTestSuccess(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &zoneMockController{})

	body := `{"origin":"lan","content":"$ORIGIN lan.\nwww IN A 10.0.0.1\n","ttl":300}`
	w := callZone(t, srv, "/api/v1/dns/zone/test", http.MethodPost, body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[ZoneTestResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Data.Success {
		t.Fatalf("预览应成功: %+v", res.Data)
	}
	if len(res.Data.Records) != 1 || !strings.Contains(res.Data.Records[0], "10.0.0.1") {
		t.Fatalf("预览记录不符: %+v", res.Data.Records)
	}
}

// 语法错误属于预期输入而非服务异常：仍返回 200，由 Success 字段承载结论
func TestServer_ZoneTestBadZoneReturns200(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &zoneMockController{})

	w := callZone(t, srv, "/api/v1/dns/zone/test", http.MethodPost,
		`{"origin":"lan","content":"not a zone file !!!","ttl":300}`)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body = %s", w.Code, w.Body.String())
	}

	var res Response[ZoneTestResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data.Success {
		t.Fatalf("顶层应成功而解析结论应为失败: %+v", res)
	}
	if res.Data.Error == "" {
		t.Fatal("应给出解析失败原因")
	}
}

func TestServer_ZoneTestRejectsInclude(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &zoneMockController{})

	w := callZone(t, srv, "/api/v1/dns/zone/test", http.MethodPost,
		`{"origin":"lan","content":"$INCLUDE /etc/passwd\n","ttl":300}`)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var res Response[ZoneTestResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if res.Data.Success {
		t.Fatal("$INCLUDE 必须被拒绝")
	}
	if !strings.Contains(res.Data.Error, "INCLUDE") {
		t.Fatalf("错误信息应指出 $INCLUDE，实得 %q", res.Data.Error)
	}
}

func TestServer_ZoneTestMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &zoneMockController{})

	if w := callZone(t, srv, "/api/v1/dns/zone/test", http.MethodGet, ""); w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}
