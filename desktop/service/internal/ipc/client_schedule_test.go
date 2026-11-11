package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

// GetBlockingSchedule 获取分时拦截（时间计划）配置与实时生效状态
func (c *Client) GetBlockingSchedule(ctx context.Context) (*ScheduleConfigResponse, error) {
	var resp Response[*ScheduleConfigResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/filter/schedule", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取时间计划失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// ConfigureBlockingSchedule 更新分时拦截（时间计划）配置
func (c *Client) ConfigureBlockingSchedule(ctx context.Context, req ConfigureScheduleRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("序列化时间计划配置失败: %w", err)
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/schedule", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("更新时间计划失败: %s", resp.Error)
	}
	return nil
}
