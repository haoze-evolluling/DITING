package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"

	"github.com/haoze-evolluling/diting/server/internal/querylog"
)

// GetQueryLog 检索查询历史
func (c *Client) GetQueryLog(ctx context.Context, q querylog.SearchQuery) (*querylog.SearchResult, error) {
	vals := url.Values{}
	if q.Domain != "" {
		vals.Set("domain", q.Domain)
	}
	if q.Client != "" {
		vals.Set("client", q.Client)
	}
	if q.QType != "" {
		vals.Set("qtype", q.QType)
	}
	if q.RCode != "" {
		vals.Set("rcode", q.RCode)
	}
	if q.Status != "" {
		vals.Set("status", q.Status)
	}
	if q.StartMs > 0 {
		vals.Set("startMs", strconv.FormatInt(q.StartMs, 10))
	}
	if q.EndMs > 0 {
		vals.Set("endMs", strconv.FormatInt(q.EndMs, 10))
	}
	if q.Limit > 0 {
		vals.Set("limit", strconv.Itoa(q.Limit))
	}
	if q.Offset > 0 {
		vals.Set("offset", strconv.Itoa(q.Offset))
	}
	if !q.IncludeFile {
		vals.Set("includeFile", "0")
	}
	path := "/api/v1/querylog/search"
	if qStr := vals.Encode(); qStr != "" {
		path += "?" + qStr
	}

	var resp Response[*querylog.SearchResult]
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("查询历史检索失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// GetQueryStats 获取查询统计中心聚合数据
func (c *Client) GetQueryStats(ctx context.Context) (*QueryStatsResponse, error) {
	var resp Response[*QueryStatsResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/querylog/stats", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取查询统计失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// ClearQueryLog 清空查询历史与统计
func (c *Client) ClearQueryLog(ctx context.Context) error {
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/querylog/clear", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("清空查询历史失败: %s", resp.Error)
	}
	return nil
}

// GetQueryLogConfig 获取查询日志配置
func (c *Client) GetQueryLogConfig(ctx context.Context) (*querylog.QueryLogConfig, error) {
	var resp Response[*querylog.QueryLogConfig]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/querylog/config", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取查询日志配置失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// UpdateQueryLogConfig 更新查询日志配置
func (c *Client) UpdateQueryLogConfig(ctx context.Context, cfg querylog.QueryLogConfig) error {
	data, err := json.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("序列化查询日志配置失败: %w", err)
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/querylog/config", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("更新查询日志配置失败: %s", resp.Error)
	}
	return nil
}
