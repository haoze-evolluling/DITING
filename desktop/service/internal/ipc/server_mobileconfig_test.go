package ipc

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

const pathMobileConfig = "/api/v1/encrypted/mobileconfig"

// callMobileConfig 直接调用处理器：该路由不经 withAuth，令牌靠查询串传递
func callMobileConfig(t *testing.T, srv *Server, method, target string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, nil)
	w := httptest.NewRecorder()
	srv.handleEncryptedMobileConfig(w, req)
	return w
}

func TestServer_MobileConfigDownload(t *testing.T) {
	ctrl := &mockController{}
	ctrl.mobileConfigData = []byte(`<?xml version="1.0"?><plist version="1.0"></plist>`)
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callMobileConfig(t, srv, http.MethodGet, pathMobileConfig+"?token=secret-token")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	// 设备靠媒体类型识别这份文件，必须精确匹配
	if got := w.Header().Get("Content-Type"); got != core.MobileConfigContentType {
		t.Fatalf("Content-Type = %q, want %q", got, core.MobileConfigContentType)
	}
	disp := w.Header().Get("Content-Disposition")
	if !strings.Contains(disp, "attachment") || !strings.Contains(disp, core.MobileConfigFileExt) {
		t.Fatalf("Content-Disposition 不符: %q", disp)
	}
	// 描述文件里含内网地址，不能被任何中间层缓存
	if got := w.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}
	if got := w.Body.String(); !strings.Contains(got, "<plist") {
		t.Fatalf("响应体不像描述文件: %q", got)
	}
}

// 空 protocol 要原样转交，由控制器决定挑哪个协议
func TestServer_MobileConfigPassesProtocol(t *testing.T) {
	ctrl := &mockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	callMobileConfig(t, srv, http.MethodGet, pathMobileConfig+"?token=secret-token")
	if ctrl.mobileConfigProtocol != "" {
		t.Fatalf("未指定协议时应传空，实得 %q", ctrl.mobileConfigProtocol)
	}

	callMobileConfig(t, srv, http.MethodGet, pathMobileConfig+"?token=secret-token&protocol=TLS")
	if ctrl.mobileConfigProtocol != "TLS" {
		t.Fatalf("协议未透传，实得 %q", ctrl.mobileConfigProtocol)
	}
}

// 未携带令牌必须挡下：这条路径暴露内网 DoH 地址
func TestServer_MobileConfigRequiresToken(t *testing.T) {
	ctrl := &mockController{}
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	for _, target := range []string{
		pathMobileConfig,
		pathMobileConfig + "?token=wrong",
	} {
		if w := callMobileConfig(t, srv, http.MethodGet, target); w.Code != http.StatusUnauthorized {
			t.Fatalf("%s: status = %d, want 401", target, w.Code)
		}
	}
}

func TestServer_MobileConfigMethodNotAllowed(t *testing.T) {
	srv := NewServer("127.0.0.1:0", "secret-token", &mockController{})
	for _, method := range []string{http.MethodPost, http.MethodDelete, http.MethodPut} {
		w := callMobileConfig(t, srv, method, pathMobileConfig+"?token=secret-token")
		if w.Code != http.StatusMethodNotAllowed {
			t.Fatalf("%s: status = %d, want 405", method, w.Code)
		}
	}
}

// HEAD 只回头部：设备与浏览器有时会先探一次
func TestServer_MobileConfigHead(t *testing.T) {
	ctrl := &mockController{}
	ctrl.mobileConfigData = []byte("<plist version=\"1.0\"></plist>")
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callMobileConfig(t, srv, http.MethodHead, pathMobileConfig+"?token=secret-token")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if w.Body.Len() != 0 {
		t.Fatalf("HEAD 不应带响应体，实得 %q", w.Body.String())
	}
	if got := w.Header().Get("Content-Type"); got != core.MobileConfigContentType {
		t.Fatalf("HEAD 仍应给出媒体类型，实得 %q", got)
	}
}

// 配置不全属于使用者需要修正的状态，用 400 让界面当成表单错误
func TestServer_MobileConfigBuildFailureIsBadRequest(t *testing.T) {
	ctrl := &mockController{}
	ctrl.mobileConfigErr = true
	srv := NewServer("127.0.0.1:0", "secret-token", ctrl)

	w := callMobileConfig(t, srv, http.MethodGet, pathMobileConfig+"?token=secret-token")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}
