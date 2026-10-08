package core

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	defaultDoHConnectTimeout = 3 * time.Second
	defaultDoHQueryTimeout   = 5 * time.Second
)

// DoHResolver 实现基于 DNS-over-HTTPS (RFC 8484) 的解析器
type DoHResolver struct {
	mu         sync.RWMutex
	bootstrap  *BootstrapResolver
	customTLS  *tls.Config
	httpClient *http.Client
}

// NewDoHResolver 创建 DoH 解析器实例
func NewDoHResolver(bootstrap *BootstrapResolver) *DoHResolver {
	d := &DoHResolver{
		bootstrap: bootstrap,
	}
	d.httpClient = d.buildHTTPClient(bootstrap)
	return d
}

// SetTLSConfig 设置自定义 TLS 配置（供测试或注入自签名证书使用）
func (d *DoHResolver) SetTLSConfig(cfg *tls.Config) {
	d.mu.Lock()
	d.customTLS = cfg
	oldClient := d.httpClient
	d.httpClient = d.buildHTTPClient(d.bootstrap)
	d.mu.Unlock()

	if oldClient != nil {
		oldClient.CloseIdleConnections()
	}
}

// SetBootstrap 更新引导解析器并重建 HTTP 客户端连接池
func (d *DoHResolver) SetBootstrap(bootstrap *BootstrapResolver) {
	d.mu.Lock()
	oldClient := d.httpClient
	d.bootstrap = bootstrap
	d.httpClient = d.buildHTTPClient(bootstrap)
	d.mu.Unlock()

	if oldClient != nil {
		oldClient.CloseIdleConnections()
	}
}

func (d *DoHResolver) buildHTTPClient(bootstrap *BootstrapResolver) *http.Client {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			target := address
			if bootstrap != nil && bootstrap.IsEnabled() {
				if host, port, err := net.SplitHostPort(address); err == nil {
					if resolvedIP, rErr := bootstrap.ResolveHost(ctx, host); rErr == nil && resolvedIP != "" {
						target = net.JoinHostPort(strings.Trim(resolvedIP, "[]"), port)
					}
				}
			}
			dialer := &net.Dialer{
				Timeout: defaultDoHConnectTimeout,
			}
			return dialer.DialContext(ctx, network, target)
		},
		ForceAttemptHTTP2:   true,
		MaxIdleConns:        10,
		MaxIdleConnsPerHost: 5,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: defaultDoHConnectTimeout,
	}

	if d.customTLS != nil {
		transport.TLSClientConfig = d.customTLS.Clone()
	}

	return &http.Client{
		Transport: transport,
		Timeout:   defaultDoHQueryTimeout,
	}
}

// Exchange 发送 wire 格式 DNS 查询至 DoH 服务器并返回响应体
func (d *DoHResolver) Exchange(ctx context.Context, rawQuery []byte, dohURL string) ([]byte, error) {
	if strings.TrimSpace(dohURL) == "" {
		return nil, fmt.Errorf("empty doh url")
	}

	d.mu.RLock()
	client := d.httpClient
	d.mu.RUnlock()

	var resp *http.Response
	var err error

	for attempt := 1; attempt <= 2; attempt++ {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		req, reqErr := http.NewRequestWithContext(ctx, http.MethodPost, dohURL, bytes.NewReader(rawQuery))
		if reqErr != nil {
			return nil, fmt.Errorf("create doh request: %w", reqErr)
		}
		req.Header.Set("Content-Type", "application/dns-message")
		req.Header.Set("Accept", "application/dns-message")

		resp, err = client.Do(req)
		if err == nil {
			break
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		// 若遇到 HTTP/2 连接因闲置被对端断开引发的 EOF，快速重试一次
		if strings.Contains(err.Error(), "EOF") && attempt == 1 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(10 * time.Millisecond):
			}
			continue
		}
		return nil, fmt.Errorf("doh request to %s failed: %w", dohURL, err)
	}

	defer resp.Body.Close()

	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusForbidden {
		return nil, fmt.Errorf("doh upstream rate limited or forbidden (status %d)", resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("doh upstream returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 65535))
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("read doh response body: %w", err)
	}

	if len(body) < 12 { // 标准 DNS 报文头至少 12 字节
		return nil, fmt.Errorf("doh response too short: %d bytes", len(body))
	}

	return body, nil
}

// Close 关闭 HTTP 客户端所有空闲连接
func (d *DoHResolver) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.httpClient != nil {
		d.httpClient.CloseIdleConnections()
	}
	return nil
}
