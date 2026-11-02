package ipc

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIPC_BackgroundEndpoints(t *testing.T) {
	mockCtrl := &mockController{
		authInitialized: true,
	}
	server := NewServer("127.0.0.1:0", "test-token", mockCtrl)

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/auth/background", server.handleAuthBackground)
	mux.HandleFunc("/api/v1/auth/background/image", server.handleAuthBackgroundImage)

	// 1. GET 初始默认背景 (未设置，返回 none 和空 URL)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/auth/background", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var getResp Response[LoginBackgroundResponse]
	if err := json.Unmarshal(rec.Body.Bytes(), &getResp); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if !getResp.Success || getResp.Data.URL != "" || getResp.Data.Type != "none" {
		t.Fatalf("unexpected default background: %+v", getResp.Data)
	}

	// 2. 本地回环免密 POST 设置自定义背景
	setPayload := SetLoginBackgroundRequest{
		Type:    "url",
		URL:     "https://example.com/wallpaper.jpg",
		Opacity: 55,
		Blur:    8,
	}
	body, _ := json.Marshal(setPayload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/background", bytes.NewReader(body))
	req.RemoteAddr = "127.0.0.1:54321" // loopback
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("loopback set background failed with status %d: %s", rec.Code, rec.Body.String())
	}
	if mockCtrl.bgConfig.URL != "https://example.com/wallpaper.jpg" || mockCtrl.bgConfig.Opacity != 55 {
		t.Fatalf("unexpected mock background state: %+v", mockCtrl.bgConfig)
	}

	// 3. 模拟局域网远程无凭证访问 (已初始化密码)，期望返回 401
	body, _ = json.Marshal(setPayload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/background", bytes.NewReader(body))
	req.RemoteAddr = "192.168.1.188:54321" // remote
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated remote request, got %d", rec.Code)
	}

	// 4. 远程访问携带正确管理员密码，期望成功
	setPayload.AdminPassword = "correct-pass"
	body, _ = json.Marshal(setPayload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/background", bytes.NewReader(body))
	req.RemoteAddr = "192.168.1.188:54321" // remote
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 with admin password, got %d: %s", rec.Code, rec.Body.String())
	}
	var postResp Response[LoginBackgroundResponse]
	if err := json.Unmarshal(rec.Body.Bytes(), &postResp); err != nil {
		t.Fatalf("unmarshal post response failed: %v", err)
	}
	if !postResp.Success || postResp.Data.URL != "https://example.com/wallpaper.jpg" {
		t.Fatalf("unexpected post response data: %+v", postResp)
	}

	// 5. 远程访问携带错误管理员密码，期望返回 401
	setPayload.AdminPassword = "wrong-pass"
	body, _ = json.Marshal(setPayload)
	req = httptest.NewRequest(http.MethodPost, "/api/v1/auth/background", bytes.NewReader(body))
	req.RemoteAddr = "192.168.1.188:54321" // remote
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 with wrong password, got %d", rec.Code)
	}

	// 6. DELETE 恢复默认系统背景
	req = httptest.NewRequest(http.MethodDelete, "/api/v1/auth/background", nil)
	req.RemoteAddr = "127.0.0.1:54321" // loopback
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("delete background failed: %d", rec.Code)
	}
	var deleteResp Response[LoginBackgroundResponse]
	if err := json.Unmarshal(rec.Body.Bytes(), &deleteResp); err != nil {
		t.Fatalf("unmarshal delete response failed: %v", err)
	}
	if !deleteResp.Success || deleteResp.Data.Type != "none" || deleteResp.Data.URL != "" {
		t.Fatalf("expected reset background in response: %+v", deleteResp)
	}
	if mockCtrl.bgConfig.Type != "none" || mockCtrl.bgConfig.URL != "" {
		t.Fatalf("expected reset background, got: %+v", mockCtrl.bgConfig)
	}

	// 7. 图片二进制流服务测试 (未上传时 404，有图片时 200 及 ETag 304)
	req = httptest.NewRequest(http.MethodGet, "/api/v1/auth/background/image", nil)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for missing image, got %d", rec.Code)
	}

	mockCtrl.bgImageData = []byte("RIFF1234WEBPTESTIMAGE")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for existing image, got %d", rec.Code)
	}
	etag := rec.Header().Get("ETag")
	if etag == "" {
		t.Fatalf("missing ETag header")
	}

	// 带 If-None-Match 请求测试 304 缓存协商
	reqWithEtag := httptest.NewRequest(http.MethodGet, "/api/v1/auth/background/image", nil)
	reqWithEtag.Header.Set("If-None-Match", etag)
	recEtag := httptest.NewRecorder()
	mux.ServeHTTP(recEtag, reqWithEtag)
	if recEtag.Code != http.StatusNotModified {
		t.Fatalf("expected 304 Not Modified, got %d", recEtag.Code)
	}
}
