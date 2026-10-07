package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/ipc"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
	miekgdns "github.com/miekg/dns"
)

// ConfigureUpstream 实现 ServiceController 接口
func (p *program) ConfigureUpstream(ctx context.Context, req ipc.ConfigureUpstreamRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.Upstream
	if req.Mode != "" {
		cfg.Mode = req.Mode
	}
	if len(req.Providers) > 0 {
		cfg.Providers = req.Providers
	}
	if p.resolver != nil {
		if err := p.resolver.Configure(cfg); err != nil {
			return err
		}
	}
	p.cfg.Upstream = cfg
	return nil
}

// TestUpstream 实现 ServiceController 接口
func (p *program) TestUpstream(ctx context.Context, req ipc.TestUpstreamRequest) (*ipc.TestUpstreamResponse, error) {
	targetServer := req.Server
	if targetServer == "" && req.URL != "" {
		targetServer = req.URL
	}
	if targetServer == "" {
		return &ipc.TestUpstreamResponse{Success: false, Error: "未指定服务器地址"}, nil
	}

	proto := strings.ToUpper(req.Protocol)
	if proto == "" {
		proto = "PLAIN"
	}

	m := new(miekgdns.Msg)
	m.SetQuestion("dns.alidns.com.", miekgdns.TypeA)
	m.RecursionDesired = true

	start := time.Now()
	var err error

	if proto == "DOH" {
		urlStr := req.URL
		if urlStr == "" {
			urlStr = req.Server
			if !strings.HasPrefix(urlStr, "http://") && !strings.HasPrefix(urlStr, "https://") {
				urlStr = "https://" + urlStr
			}
			if !strings.Contains(urlStr, "/dns-query") {
				urlStr = strings.TrimRight(urlStr, "/") + "/dns-query"
			}
		}

		rawQuery, packErr := m.Pack()
		if packErr != nil {
			return &ipc.TestUpstreamResponse{Success: false, Error: fmt.Sprintf("打包 DNS 报文失败: %v", packErr)}, nil
		}

		httpReq, httpErr := http.NewRequestWithContext(ctx, http.MethodPost, urlStr, bytes.NewReader(rawQuery))
		if httpErr != nil {
			return &ipc.TestUpstreamResponse{Success: false, Error: httpErr.Error()}, nil
		}
		httpReq.Header.Set("Content-Type", "application/dns-message")
		httpReq.Header.Set("Accept", "application/dns-message")

		c := &http.Client{Timeout: 3 * time.Second}
		resp, httpErr := c.Do(httpReq)
		if httpErr != nil {
			return &ipc.TestUpstreamResponse{Success: false, Error: httpErr.Error()}, nil
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return &ipc.TestUpstreamResponse{Success: false, Error: fmt.Sprintf("HTTP 响应状态异常: %d", resp.StatusCode)}, nil
		}

		body, readErr := io.ReadAll(io.LimitReader(resp.Body, 65535))
		if readErr != nil {
			return &ipc.TestUpstreamResponse{Success: false, Error: readErr.Error()}, nil
		}

		respMsg := new(miekgdns.Msg)
		if unpackErr := respMsg.Unpack(body); unpackErr != nil {
			return &ipc.TestUpstreamResponse{Success: false, Error: fmt.Sprintf("DNS 解析解包失败: %v", unpackErr)}, nil
		}
	} else if proto == "DOT" {
		dotAddr := targetServer
		if !strings.Contains(dotAddr, ":") {
			dotAddr += ":853"
		}
		c := &miekgdns.Client{Net: "tcp-tls", Timeout: 3 * time.Second}
		_, _, err = c.ExchangeContext(ctx, m, dotAddr)
	} else {
		plainAddr := targetServer
		if !strings.Contains(plainAddr, ":") {
			plainAddr += ":53"
		}
		c := &miekgdns.Client{Net: "udp", Timeout: 3 * time.Second}
		_, _, err = c.ExchangeContext(ctx, m, plainAddr)
	}

	latency := float64(time.Since(start).Nanoseconds()) / 1e6
	if err != nil {
		return &ipc.TestUpstreamResponse{Success: false, LatencyMs: latency, Error: err.Error()}, nil
	}
	return &ipc.TestUpstreamResponse{Success: true, LatencyMs: latency}, nil
}

// SetAdapterTakeover 实现 ServiceController 接口
func (p *program) SetAdapterTakeover(ctx context.Context, req ipc.AdapterTakeoverRequest) error {
	if req.Enable {
		adapters, err := p.adapterScan.ScanAll(ctx)
		if err != nil {
			return err
		}
		var target *windows.AdapterInfo
		for _, a := range adapters {
			if a.ID == req.AdapterID || a.Name == req.AdapterID {
				curr := a
				target = &curr
				break
			}
		}
		if target == nil {
			return fmt.Errorf("找不到网卡: %s", req.AdapterID)
		}
		return p.takeoverMgr.TakeoverSingle(ctx, *target)
	}
	return p.takeoverMgr.RestoreSingle(ctx, req.AdapterID)
}
