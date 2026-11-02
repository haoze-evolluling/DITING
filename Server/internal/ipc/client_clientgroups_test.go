package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// GetClientGroups 获取客户端分组配置与可选订阅列表
func (c *Client) GetClientGroups(ctx context.Context) (*ClientGroupConfigResponse, error) {
	var resp Response[*ClientGroupConfigResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/clients/groups", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取客户端分组失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// ConfigureClientGroups 更新客户端分组配置
func (c *Client) ConfigureClientGroups(ctx context.Context, req ConfigureClientGroupsRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("序列化客户端分组配置失败: %w", err)
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/clients/groups", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("更新客户端分组失败: %s", resp.Error)
	}
	return nil
}
