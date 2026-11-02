package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// GetLANStatus 获取局域网 DNS 服务状态
func (c *Client) GetLANStatus(ctx context.Context) (*LANStatusResponse, error) {
	var resp Response[*LANStatusResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/dns/lan", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取局域网 DNS 状态失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// ConfigureLAN 配置局域网 DNS 服务模式
func (c *Client) ConfigureLAN(ctx context.Context, req ConfigureLANRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/dns/lan/configure", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("配置局域网 DNS 失败: %s", resp.Error)
	}
	return nil
}

// ConfigureFirewall 配置 Windows 防火墙 53 端口放行规则
func (c *Client) ConfigureFirewall(ctx context.Context, enable bool) error {
	data, err := json.Marshal(ConfigureFirewallRequest{Enable: enable})
	if err != nil {
		return err
	}
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/dns/lan/firewall", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("配置防火墙规则失败: %s", resp.Error)
	}
	return nil
}
