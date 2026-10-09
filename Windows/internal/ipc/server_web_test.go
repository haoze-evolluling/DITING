package ipc

import (
	"context"
	"errors"
	"io"
	"net/http"
	"testing"
	"testing/fstest"
)

// 为 mockController 补充 Web 与 Auth 相关实现
func (m *mockController) GetWebStatus(ctx context.Context) (*WebStatusResponse, error) {
	return &WebStatusResponse{
		Enabled:         true,
		Port:            15353,
		ListenAddress:   "0.0.0.0:15353",
		LANAddresses:    []string{"192.168.1.100"},
		WebURLs:         []string{"http://192.168.1.100:15353"},
		FirewallAllowed: true,
		Initialized:     true,
		Username:        "admin",
	}, nil
}

func (m *mockController) ConfigureWeb(ctx context.Context, req ConfigureWebRequest) error {
	return nil
}

func (m *mockController) ConfigureWebFirewall(ctx context.Context, enable bool) error {
	return nil
}

func (m *mockController) GetAuthStatus(ctx context.Context) (*AuthStatusResponse, error) {
	return &AuthStatusResponse{
		Initialized:   true,
		WebEnabled:    true,
		Authenticated: true,
		Username:      "admin",
	}, nil
}

func (m *mockController) Login(ctx context.Context, req LoginRequest, clientIP string) (*LoginResponse, error) {
	if req.Username == "admin" && req.Password == "correctpass" {
		return &LoginResponse{
			Token:     "mock-session-token",
			Username:  "admin",
			ExpiresAt: 9999999999,
		}, nil
	}
	return nil, errors.New("用户名或密码错误")
}

func (m *mockController) Logout(ctx context.Context, token string) error {
	return nil
}

func (m *mockController) SetupAuth(ctx context.Context, req SetupAuthRequest) error {
	return nil
}

func (m *mockController) ChangePassword(ctx context.Context, req ChangePasswordRequest, bypassOldAuth bool) error {
	return nil
}

func (m *mockController) ValidateSession(token string) bool {
	return token == "mock-session-token"
}

func TestIPC_WebAndAuthEndpoints(t *testing.T) {
	mockCtrl := &mockController{}
	token := "ipc-secret-token"
	server := NewServer("127.0.0.1:0", token, mockCtrl)

	// 设置测试静态文件系统
	mockFS := fstest.MapFS{
		"index.html": &fstest.MapFile{Data: []byte("<!DOCTYPE html><html><body>Diting Test SPA</body></html>")},
		"assets/test.js": &fstest.MapFile{Data: []byte("console.log('test');")},
	}
	server.SetAssetsFS(mockFS)

	if err := server.Start(); err != nil {
		t.Fatalf("server.Start failed: %v", err)
	}
	defer func() { _ = server.Shutdown(context.Background()) }()

	client := NewClient(server.Addr(), token)
	ctx := context.Background()

	// 1. 获取认证概览状态
	authStatus, err := client.GetAuthStatus(ctx)
	if err != nil {
		t.Fatalf("GetAuthStatus failed: %v", err)
	}
	if !authStatus.Initialized || authStatus.Username != "admin" {
		t.Errorf("unexpected auth status: %+v", authStatus)
	}

	// 2. 测试初始化密码
	err = client.SetupAuth(ctx, SetupAuthRequest{Username: "admin", Password: "newpassword123"})
	if err != nil {
		t.Fatalf("SetupAuth failed: %v", err)
	}

	// 3. 测试错误密码登录
	_, err = client.Login(ctx, LoginRequest{Username: "admin", Password: "wrong"})
	if err == nil {
		t.Fatalf("expected login failure with wrong password")
	}

	// 4. 测试正确密码登录
	loginResp, err := client.Login(ctx, LoginRequest{Username: "admin", Password: "correctpass"})
	if err != nil {
		t.Fatalf("Login failed: %v", err)
	}
	if loginResp.Token != "mock-session-token" {
		t.Errorf("unexpected token: %s", loginResp.Token)
	}

	// 5. 测试修改密码
	err = client.ChangePassword(ctx, ChangePasswordRequest{Username: "admin", NewPassword: "changedpass"})
	if err != nil {
		t.Fatalf("ChangePassword failed: %v", err)
	}

	// 6. 测试获取 Web 状态
	webStatus, err := client.GetWebStatus(ctx)
	if err != nil {
		t.Fatalf("GetWebStatus failed: %v", err)
	}
	if !webStatus.Enabled || webStatus.Port != 15353 {
		t.Errorf("unexpected web status: %+v", webStatus)
	}

	// 7. 测试配置 Web 管理
	err = client.ConfigureWeb(ctx, ConfigureWebRequest{Enabled: true, Port: 15353, ConfigureFirewall: true})
	if err != nil {
		t.Fatalf("ConfigureWeb failed: %v", err)
	}

	// 8. 测试 Web 防火墙开关
	err = client.ConfigureWebFirewall(ctx, true)
	if err != nil {
		t.Fatalf("ConfigureWebFirewall failed: %v", err)
	}

	// 9. 测试注销登录
	err = client.Logout(ctx)
	if err != nil {
		t.Fatalf("Logout failed: %v", err)
	}

	// 10. 测试静态 SPA 文件与路由回退
	resp, err := http.Get("http://" + server.Addr() + "/rules")
	if err != nil {
		t.Fatalf("Get SPA route failed: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK || string(body) != "<!DOCTYPE html><html><body>Diting Test SPA</body></html>" {
		t.Errorf("unexpected SPA response: code=%d body=%s", resp.StatusCode, string(body))
	}
}
