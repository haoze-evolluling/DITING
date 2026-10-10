package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

// GetFilterStats 获取规则过滤指标
func (c *Client) GetFilterStats(ctx context.Context) (*core.FilterStats, error) {
	var resp Response[*core.FilterStats]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/filter/stats", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取过滤指标失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// GetFilterConfig 获取规则过滤配置
func (c *Client) GetFilterConfig(ctx context.Context) (*core.FilterConfig, error) {
	var resp Response[*core.FilterConfig]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/filter/config", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取过滤配置失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// UpdateFilterConfig 更新规则过滤配置
func (c *Client) UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error {
	data, err := json.Marshal(cfg)
	if err != nil {
		return err
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/config", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("更新过滤配置失败: %s", resp.Error)
	}
	return nil
}

// GetFilterLists 获取订阅规则列表
func (c *Client) GetFilterLists(ctx context.Context) ([]core.FilterList, error) {
	var resp Response[*FilterListsResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/filter/lists", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取订阅列表失败: %s", resp.Error)
	}
	if resp.Data == nil {
		return nil, nil
	}
	return resp.Data.Lists, nil
}

// AddFilterList 添加新订阅列表
func (c *Client) AddFilterList(ctx context.Context, list core.FilterList) error {
	data, err := json.Marshal(list)
	if err != nil {
		return err
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/lists/add", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("添加订阅列表失败: %s", resp.Error)
	}
	return nil
}

// UpdateFilterList 更新已有的订阅列表
func (c *Client) UpdateFilterList(ctx context.Context, list core.FilterList) error {
	data, err := json.Marshal(list)
	if err != nil {
		return err
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/lists/update", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("更新订阅列表失败: %s", resp.Error)
	}
	return nil
}

// DeleteFilterList 删除订阅列表
func (c *Client) DeleteFilterList(ctx context.Context, id string) error {
	req := FilterActionRequest{ID: id}
	data, _ := json.Marshal(req)
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/lists/delete", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("删除订阅列表失败: %s", resp.Error)
	}
	return nil
}

// RefreshFilterLists 刷新指定或全部订阅列表
func (c *Client) RefreshFilterLists(ctx context.Context, id string) error {
	req := FilterActionRequest{ID: id}
	data, _ := json.Marshal(req)
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/lists/refresh", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("刷新规则源失败: %s", resp.Error)
	}
	return nil
}

// GetCustomRules 获取用户自定义规则
func (c *Client) GetCustomRules(ctx context.Context) ([]string, error) {
	var resp Response[*FilterRulesResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/filter/rules", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取自定义规则失败: %s", resp.Error)
	}
	if resp.Data == nil {
		return nil, nil
	}
	return resp.Data.Rules, nil
}

// SetCustomRules 保存用户自定义规则
func (c *Client) SetCustomRules(ctx context.Context, rules []string) error {
	req := core.UpdateRulesRequest{Rules: rules}
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/rules", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("保存自定义规则失败: %s", resp.Error)
	}
	return nil
}

// CheckHost 规则检测
func (c *Client) CheckHost(ctx context.Context, domain, qtype string) (*core.CheckHostResult, error) {
	req := core.CheckDomainRequest{Domain: domain, QType: qtype}
	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	var resp Response[*core.CheckHostResult]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/filter/check", bytes.NewReader(data), &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("检测域名失败: %s", resp.Error)
	}
	return resp.Data, nil
}
