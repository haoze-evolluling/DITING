package ipc

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// Client 用于与 diting-service 进行 REST 及 WebSocket 通信的 IPC 客户端
type Client struct {
	baseURL    string
	token      string
	httpClient *http.Client
}

// NewClient 创建 IPC 客户端
func NewClient(baseURL, token string) *Client {
	base := strings.TrimRight(baseURL, "/")
	if !strings.HasPrefix(base, "http://") && !strings.HasPrefix(base, "https://") {
		base = "http://" + base
	}
	return &Client{
		baseURL: base,
		token:   token,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// GetStatus 获取服务完整运行状态
func (c *Client) GetStatus(ctx context.Context) (*StatusResponse, error) {
	var resp Response[*StatusResponse]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/status", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取状态失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// StartDNS 启动 DNS 监听器
func (c *Client) StartDNS(ctx context.Context) error {
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/dns/start", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("启动 DNS 失败: %s", resp.Error)
	}
	return nil
}

// StopDNS 停止 DNS 监听器
func (c *Client) StopDNS(ctx context.Context) error {
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/dns/stop", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("停止 DNS 失败: %s", resp.Error)
	}
	return nil
}

// EnableTakeover 开启物理网卡 DNS 接管
func (c *Client) EnableTakeover(ctx context.Context) error {
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/takeover/enable", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("开启接管失败: %s", resp.Error)
	}
	return nil
}

// DisableTakeover 关闭物理网卡 DNS 接管并还原
func (c *Client) DisableTakeover(ctx context.Context) error {
	var resp Response[any]
	if err := c.doRequest(ctx, http.MethodPost, "/api/v1/takeover/disable", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("关闭接管失败: %s", resp.Error)
	}
	return nil
}

// CheckPortConflicts 诊断 53 端口冲突
func (c *Client) CheckPortConflicts(ctx context.Context) (*windows.PortCheckResult, error) {
	var resp Response[*windows.PortCheckResult]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/portcheck", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("端口诊断失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// GetAdapters 枚举系统所有网卡详情
func (c *Client) GetAdapters(ctx context.Context) ([]windows.AdapterInfo, error) {
	var resp Response[[]windows.AdapterInfo]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/adapters", nil, &resp); err != nil {
		return nil, err
	}
	if !resp.Success {
		return nil, fmt.Errorf("获取网卡列表失败: %s", resp.Error)
	}
	return resp.Data, nil
}

// HealthCheck 健康探针检测
func (c *Client) HealthCheck(ctx context.Context) error {
	var resp Response[string]
	if err := c.doRequest(ctx, http.MethodGet, "/api/v1/health", nil, &resp); err != nil {
		return err
	}
	if !resp.Success {
		return fmt.Errorf("健康检查失败: %s", resp.Error)
	}
	return nil
}

// SubscribeEvents 订阅实时 WebSocket 事件流
func (c *Client) SubscribeEvents(ctx context.Context) (<-chan Event, func(), error) {
	wsURL := c.baseURL + "/api/v1/events"
	if strings.HasPrefix(wsURL, "https://") {
		wsURL = "wss://" + strings.TrimPrefix(wsURL, "https://")
	} else {
		wsURL = "ws://" + strings.TrimPrefix(wsURL, "http://")
	}

	u, err := url.Parse(wsURL)
	if err != nil {
		return nil, nil, err
	}
	if c.token != "" {
		q := u.Query()
		q.Set("token", c.token)
		u.RawQuery = q.Encode()
	}

	header := make(http.Header)
	if c.token != "" {
		header.Set("Authorization", "Bearer "+c.token)
	}

	dialer := websocket.DefaultDialer
	conn, _, err := dialer.DialContext(ctx, u.String(), header)
	if err != nil {
		return nil, nil, fmt.Errorf("连接 WebSocket 失败: %w", err)
	}

	eventsCh := make(chan Event, 64)
	closeOnce := make(chan struct{})

	cancelFunc := func() {
		select {
		case <-closeOnce:
		default:
			close(closeOnce)
			_ = conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
			_ = conn.Close()
		}
	}

	go func() {
		defer func() {
			cancelFunc()
			close(eventsCh)
		}()
		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				return
			}
			var evt Event
			if err := json.Unmarshal(msg, &evt); err == nil {
				select {
				case eventsCh <- evt:
				case <-closeOnce:
					return
				}
			}
		}
	}()

	return eventsCh, cancelFunc, nil
}

func (c *Client) doRequest(ctx context.Context, method, path string, body io.Reader, out any) error {
	reqURL := c.baseURL + path
	req, err := http.NewRequestWithContext(ctx, method, reqURL, body)
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("IPC 请求失败: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("读取响应失败: %w", err)
	}

	if resp.StatusCode == http.StatusUnauthorized {
		return fmt.Errorf("401 unauthorized: 鉴权失败")
	}

	if out != nil {
		if err := json.Unmarshal(data, out); err != nil {
			return fmt.Errorf("解析响应 JSON 失败 (状态码: %d): %w (响应体: %s)", resp.StatusCode, err, string(data))
		}
	}
	return nil
}
