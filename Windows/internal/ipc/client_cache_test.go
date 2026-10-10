package ipc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"

	"github.com/haoze-evolluling/diting/windows/internal/core"
)

// GetCacheStats 获取智能缓存统计指标
func (c *Client) GetCacheStats(ctx context.Context) (*core.CacheStats, error) {
	var resp Response[*core.CacheStats]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/cache/stats", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取缓存指标失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// GetCacheEntries 获取智能缓存条目列表
func (c *Client) GetCacheEntries(ctx context.Context, query string, limit int) (*CacheEntriesResponse, error) {
	vals := url.Values{}
	if query != "" {
		vals.Set("query", query)
	}
	if limit > 0 {
		vals.Set("limit", strconv.Itoa(limit))
	}
	path := "/api/v1/cache/entries"
	if qStr := vals.Encode(); qStr != "" {
		path += "?" + qStr
	}

	var resp Response[*CacheEntriesResponse]
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取缓存条目失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// GetCacheTopDomains 获取热点域名排行
func (c *Client) GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error) {
	path := "/api/v1/cache/top"
	if limit > 0 {
		path += "?limit=" + strconv.Itoa(limit)
	}

	var resp Response[[]core.CacheDomainStat]
	if err := c.doRequest(ctx, http.MethodGet, path, nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取热点域名排行失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// ClearCache 清空缓存
func (c *Client) ClearCache(ctx context.Context) error {
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/cache/clear", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("清空缓存失败: %s", resp.Error)
	}
	return nil
}

// GetCacheConfig 获取缓存配置
func (c *Client) GetCacheConfig(ctx context.Context) (*core.CacheConfig, error) {
	var resp Response[*core.CacheConfig]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/cache/config", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取缓存配置失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// UpdateCacheConfig 更新缓存配置
func (c *Client) UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error {
	data, err := json.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("序列化缓存配置失败: %w", err)
	}
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/cache/config", bytes.NewReader(data), &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("更新缓存配置失败: %s", resp.Error)
	}
	return nil
}
