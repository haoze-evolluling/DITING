package ipc

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

const pathACL = "/api/v1/encrypted/dns/acl"

func callACL(t *testing.T, srv *Server, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, pathACL, bytes.NewReader([]byte(body)))
	req.Header.Set("Authorization", "Bearer secret-token")
	w := httptest.NewRecorder()
	srv.handleEncryptedDNSACL(w, req)
	return w
}

func TestServer_ACLGet(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	w := callACL(t, srv, http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	var res Response[*EncryptedDNSStatusResponse]
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}
	if !res.Success || res.Data == nil {
		t.Fatalf("GET 应回传完整状态: %+v", res)
	}
}

func TestServer_ACLConfigure(t *testing.T) {
	ctrl := &mockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	body := `{"enabled":true,"trustedSources":["10.0.0.0/8","192.168.1.1"],"clientIpHeader":"CF-Connecting-IP"}`
	w := callACL(t, srv, http.MethodPost, body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	if !ctrl.aclUpdated {
		t.Fatal("请求应被转交")
	}
	got := ctrl.lastACLReq
	if got.Enabled == nil || !*got.Enabled {
		t.Fatalf("enabled 未解析: %+v", got)
	}
	if got.TrustedSources == nil || len(*got.TrustedSources) != 2 {
		t.Fatalf("trustedSources 未解析: %+v", got)
	}
	if got.ClientIPHeader == nil || *got.ClientIPHeader != "CF-Connecting-IP" {
		t.Fatalf("clientIpHeader 未解析: %+v", got)
	}
}

// 全放行配置未确认时必须被挡下：光靠界面弹窗挡不住直接调接口的人，
// 而这道配置一旦生效，任何人都能伪装成白名单成员并绕过按 IP 的限速
func TestServer_ACLUnrestrictedRequiresConfirmation(t *testing.T) {
	for _, sources := range []string{
		`["0.0.0.0/0"]`,
		`["::/0"]`,
		`["10.0.0.1","0.0.0.0/0"]`,
	} {
		for _, confirmed := range []string{"", "false"} {
			body := `{"enabled":true,"trustedSources":` + sources +
				`,"confirmUnrestricted":` + confirmed + `}`
			srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
			if w := callACL(t, srv, http.MethodPost, body); w.Code != http.StatusBadRequest {
				t.Fatalf("%s (confirm=%q): status = %d, want 400", sources, confirmed, w.Code)
			}
		}
	}
}

// 明确确认后放行，界面据此实现「二次确认」
func TestServer_ACLUnrestrictedAllowedWhenConfirmed(t *testing.T) {
	body := `{"enabled":true,"trustedSources":["0.0.0.0/0"],"confirmUnrestricted":true}`
	srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	if w := callACL(t, srv, http.MethodPost, body); w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body = %s", w.Code, w.Body.String())
	}
}

// 控制器报错走 400：调用方需要修正配置，而不是重试
func TestServer_ACLWriteErrorIsBadRequest(t *testing.T) {
	ctrl := &mockController{}
	ctrl.aclWriteErr = true
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	body := `{"trustedSources":["10.0.0.1"]}`
	if w := callACL(t, srv, http.MethodPost, body); w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

func TestServer_ACLMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	for _, method := range []string{http.MethodDelete, http.MethodPut} {
		if w := callACL(t, srv, method, ""); w.Code != http.StatusMethodNotAllowed {
			t.Fatalf("%s: status = %d, want 405", method, w.Code)
		}
	}
}

func TestServer_ACLRequiresAuth(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	req := httptest.NewRequest(http.MethodGet, pathACL, nil)
	w := httptest.NewRecorder()
	srv.withAuth(srv.handleEncryptedDNSACL)(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
}

func TestServer_ACLBadJSON(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	if w := callACL(t, srv, http.MethodPost, `{oops`); w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}
