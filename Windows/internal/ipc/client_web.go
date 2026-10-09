package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// SetToken 动态设置当前 IPC 客户端携带的鉴权或会话 Token
func (c *Client) SetToken(token string) {
	c.token = token
}

// GetAuthStatus 获取当前认证系统与 Web 服务状态
func (c *Client) GetAuthStatus(ctx context.Context) (*AuthStatusResponse, error) {
	var resp Response[*AuthStatusResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/auth/status", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取认证状态失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// Login 执行管理员账号密码登录
func (c *Client) Login(ctx context.Context, req LoginRequest) (*LoginResponse, error) {
	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	var resp Response[*LoginResponse]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/auth/login", bytes.NewReader(data), &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("登录失败: %s", resp.Error)
	}
	if resp.Data != nil && resp.Data.Token != "" {
		c.token = resp.Data.Token
	}
	return resp.Data, nil
}

// Logout 退出登录并销毁当前会话
func (c *Client) Logout(ctx context.Context) error {
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/auth/logout", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("退出登录失败: %s", resp.Error)
	}
	c.token = ""
	return nil
}

// SetupAuth 首次初始化管理员账号密码
func (c *Client) SetupAuth(ctx context.Context, req SetupAuthRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/auth/setup", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("初始化管理员账号失败: %s", resp.Error)
	}
	return nil
}

// ChangePassword 修改管理员密码
func (c *Client) ChangePassword(ctx context.Context, req ChangePasswordRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/auth/password", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("修改管理员密码失败: %s", resp.Error)
	}
	return nil
}

// GetWebStatus 获取局域网 Web 远程管理状态
func (c *Client) GetWebStatus(ctx context.Context) (*WebStatusResponse, error) {
	var resp Response[*WebStatusResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/web/status", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取 Web 远程管理状态失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// ConfigureWeb 配置局域网 Web 远程管理启停与端口
func (c *Client) ConfigureWeb(ctx context.Context, req ConfigureWebRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/web/configure", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("配置 Web 远程管理失败: %s", resp.Error)
	}
	return nil
}

// ConfigureWebFirewall 配置 Web 端口 Windows 防火墙规则
func (c *Client) ConfigureWebFirewall(ctx context.Context, enable bool) error {
	data, err := json.Marshal(ConfigureFirewallRequest{Enable: enable})
	if err != nil {
		return err
	}
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/web/firewall", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("配置 Web 防火墙规则失败: %s", resp.Error)
	}
	return nil
}
