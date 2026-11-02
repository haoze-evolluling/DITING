package ipc

import (
	"context"
	"errors"
	"io"
	"net/http"
	"testing"
	"testing/fstest"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
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

func (m *mockController) GetLoginBackground(ctx context.Context) (*LoginBackgroundResponse, error) {
	if m.bgConfig != nil {
		return m.bgConfig, nil
	}
	return &LoginBackgroundResponse{Type: "none", URL: "", Opacity: 40, Blur: 0}, nil
}

func (m *mockController) SetLoginBackground(ctx context.Context, req SetLoginBackgroundRequest) error {
	m.bgConfig = &LoginBackgroundResponse{
		Type:      req.Type,
		URL:       req.URL,
		Opacity:   req.Opacity,
		Blur:      req.Blur,
		UpdatedAt: 1730000000,
	}
	return nil
}

func (m *mockController) ResetLoginBackground(ctx context.Context) error {
	m.bgConfig = &LoginBackgroundResponse{Type: "none", URL: "", Opacity: 40, Blur: 0}
	return nil
}

func (m *mockController) GetLoginBackgroundImage(ctx context.Context) ([]byte, string, time.Time, error) {
	if m.bgImageData != nil {
		return m.bgImageData, "image/webp", time.Unix(1730000000, 0), nil
	}
	return nil, "", time.Time{}, errors.New("file not found")
}

func (m *mockController) VerifyAdminPassword(ctx context.Context, plainPassword string) bool {
	return plainPassword == "correct-pass"
}

func (m *mockController) VerifyAdminPasswordWithIP(ctx context.Context, clientIP, plainPassword string) (bool, error) {
	if plainPassword == "correct-pass" {
		return true, nil
	}
	return false, errors.New("管理员密码错误")
}

func (m *mockController) IsAuthInitialized() bool {
	return m.authInitialized
}

func (m *mockController) ConfigureAccess(ctx context.Context, req ConfigureAccessRequest) error {
	return nil
}

func (m *mockController) ConfigureRateLimit(ctx context.Context, req ConfigureRateLimitRequest) error {
	return nil
}

func (m *mockController) ConfigureDNS64(ctx context.Context, req ConfigureDNS64Request) error {
	return nil
}

func (m *mockController) ConfigureBlockUnqualified(ctx context.Context, req ConfigureBlockUnqualifiedRequest) error {
	return nil
}

func (m *mockController) ConfigurePrivacy(ctx context.Context, req ConfigurePrivacyRequest) error {
	return nil
}

func (m *mockController) GetRewriteRules(ctx context.Context) ([]core.RewriteRule, error) {
	return []core.RewriteRule{}, nil
}

func (m *mockController) AddRewriteRule(ctx context.Context, rule core.RewriteRule) error {
	return nil
}

func (m *mockController) DeleteRewriteRule(ctx context.Context, domain string) error {
	return nil
}

func (m *mockController) ConfigureRewrite(ctx context.Context, req ConfigureRewriteRequest) error {
	return nil
}

func (m *mockController) GetSafeSearch(ctx context.Context) (*SafeSearchConfigResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.safeSearch == nil {
		return &SafeSearchConfigResponse{Disabled: []string{}, TTL: 300}, nil
	}
	cpy := *m.safeSearch
	cpy.Disabled = append([]string{}, m.safeSearch.Disabled...)
	return &cpy, nil
}

func (m *mockController) ConfigureSafeSearch(ctx context.Context, req ConfigureSafeSearchRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.safeSearchErr != nil {
		return m.safeSearchErr
	}
	if m.safeSearch == nil {
		m.safeSearch = &SafeSearchConfigResponse{Disabled: []string{}, TTL: 300}
	}
	if req.Enabled != nil {
		m.safeSearch.Enabled = *req.Enabled
	}
	if req.Disabled != nil {
		m.safeSearch.Disabled = normalizeSafeSearchDisabled(*req.Disabled)
	}
	if req.TTL != nil && *req.TTL > 0 {
		m.safeSearch.TTL = *req.TTL
	}
	return nil
}

func (m *mockController) GetClients(ctx context.Context) ([]core.ClientInfo, error) {
	return []core.ClientInfo{}, nil
}

func (m *mockController) ConfigureClientAlias(ctx context.Context, req ConfigureClientAliasRequest) error {
	return nil
}

func (m *mockController) ConfigureECS(ctx context.Context, req ConfigureECSRequest) error {
	return nil
}

func (m *mockController) ConfigureRebind(ctx context.Context, req ConfigureRebindRequest) error {
	return nil
}

func (m *mockController) ConfigureHosts(ctx context.Context, req ConfigureHostsRequest) error {
	return nil
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
