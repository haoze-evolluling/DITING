package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/platform"
	miekgdns "github.com/miekg/dns"
)

// ConfigureUpstream 实现 ServiceController 接口
func (p *program) ConfigureUpstream(ctx context.Context, req ipc.ConfigureUpstreamRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cfg == nil {
		p.cfg = config.DefaultConfig()
	}

	// 基础校验：必须包含至少一个可配置字段。
	// 回退链的标量字段（超时/响应码/故障开关）同样算有效配置项，
	// 否则用户只调整"独立超时"时会被告知"未包含任何有效的上游配置项"。
	if req.Mode == "" && req.Providers == nil && req.Bootstrap == nil &&
		req.ConditionalRoutes == nil && req.FallbackProviders == nil &&
		req.FallbackTimeoutMs == nil && req.FallbackOnRcode == nil && req.FallbackOnError == nil {
		return fmt.Errorf("未包含任何有效的上游配置项")
	}

	cfg := p.cfg.Upstream

	if req.Mode != "" {
		if !core.IsValidMode(req.Mode) {
			return fmt.Errorf("不支持的上游调度模式: %s", req.Mode)
		}
		cfg.Mode = req.Mode
	}

	// 主链路与回退链路的 ID 必须全局唯一：统计指标按 ID 归集，
	// 同名节点会共享同一份健康与延迟记录，导致口径互相污染。
	seenIDs := make(map[string]bool)

	if req.Providers != nil {
		if len(req.Providers) == 0 {
			return fmt.Errorf("至少需要配置一个上游 DNS 服务器")
		}
		validated, err := validateProviderList(req.Providers, seenIDs, "")
		if err != nil {
			return err
		}
		cfg.Providers = validated
	} else {
		for _, prov := range cfg.Providers {
			seenIDs[strings.TrimSpace(prov.ID)] = true
		}
	}

	// nil 表示"保持现状"，非 nil（含空切片）表示"替换为这里给出的回退链"；
	// 传空切片即关闭回退，这是关闭该功能的唯一途径。
	if req.FallbackProviders != nil {
		validated, err := validateProviderList(req.FallbackProviders, seenIDs, "回退")
		if err != nil {
			return err
		}
		if len(validated) == 0 {
			cfg.FallbackProviders = nil
		} else {
			cfg.FallbackProviders = validated
		}
	}
	if req.FallbackTimeoutMs != nil {
		cfg.FallbackTimeoutMs = *req.FallbackTimeoutMs
	}
	if req.FallbackOnRcode != nil {
		// 复制一份，避免调用方的切片与落盘配置共享底层数组；
		// 空切片原样保留（表示"取消全部响应码触发"），不可与 nil 合并。
		cfg.FallbackOnRcode = append([]int{}, (*req.FallbackOnRcode)...)
	}
	if req.FallbackOnError != nil {
		cfg.FallbackOnError = req.FallbackOnError
	}

	if req.Bootstrap != nil {
		if err := core.ValidateBootstrapConfig(*req.Bootstrap); err != nil {
			return err
		}
		cfg.Bootstrap = *req.Bootstrap
	}

	if req.ConditionalRoutes != nil {
		cfg.ConditionalRoutes = req.ConditionalRoutes
	}

	if p.resolver != nil {
		if err := p.resolver.Configure(cfg); err != nil {
			return err
		}
		// 上游整体重建后，分组专属上游的节点指针必须重新绑定到新对象；
		// Configure 内部只保留 ID 映射，此处据分组配置重新解析一次
		p.applyGroupUpstreams(p.cfg.Client.GroupConfig())
	}

	p.cfg.Upstream = cfg

	savePath := p.configPath
	if savePath == "" {
		savePath = config.GetDefaultConfigPath()
	}
	if err := config.SaveConfig(savePath, p.cfg); err != nil {
		return fmt.Errorf("保存配置失败: %w", err)
	}

	return nil
}

// GetUpstreamConfig 实现 ServiceController 接口
func (p *program) GetUpstreamConfig(ctx context.Context) (*core.ResolverConfig, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.cfg == nil {
		return &core.ResolverConfig{}, nil
	}
	cfg := p.cfg.Upstream
	return &cfg, nil
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

		tr := &http.Transport{
			DialContext: func(dialCtx context.Context, network, address string) (net.Conn, error) {
				target := address
				if h, pt, sErr := net.SplitHostPort(address); sErr == nil {
					if resolvedIP, rErr := p.resolveHostWithBootstrap(dialCtx, h); rErr == nil && resolvedIP != "" {
						target = net.JoinHostPort(strings.Trim(resolvedIP, "[]"), pt)
					}
				}
				dialer := &net.Dialer{Timeout: 3 * time.Second}
				return dialer.DialContext(dialCtx, network, target)
			},
		}
		c := &http.Client{Transport: tr, Timeout: 3 * time.Second}
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
		host := targetServer
		port := "853"
		if h, pt, sErr := net.SplitHostPort(targetServer); sErr == nil {
			host = h
			port = pt
		}
		cleanHost := strings.Trim(host, "[]")
		dialHost := cleanHost
		if resolvedIP, rErr := p.resolveHostWithBootstrap(ctx, cleanHost); rErr == nil && resolvedIP != "" {
			dialHost = resolvedIP
		}
		dotAddr := net.JoinHostPort(strings.Trim(dialHost, "[]"), port)
		c := &miekgdns.Client{
			Net: "tcp-tls",
			TLSConfig: &tls.Config{
				ServerName: cleanHost,
			},
			Timeout: 3 * time.Second,
		}
		_, _, err = c.ExchangeContext(ctx, m, dotAddr)
	} else {
		host := targetServer
		port := "53"
		if h, pt, sErr := net.SplitHostPort(targetServer); sErr == nil {
			host = h
			port = pt
		}
		cleanHost := strings.Trim(host, "[]")
		dialHost := cleanHost
		if resolvedIP, rErr := p.resolveHostWithBootstrap(ctx, cleanHost); rErr == nil && resolvedIP != "" {
			dialHost = resolvedIP
		}
		plainAddr := net.JoinHostPort(strings.Trim(dialHost, "[]"), port)
		c := &miekgdns.Client{Net: "udp", Timeout: 3 * time.Second}
		_, _, err = c.ExchangeContext(ctx, m, plainAddr)
	}

	latency := float64(time.Since(start).Nanoseconds()) / 1e6
	if err != nil {
		return &ipc.TestUpstreamResponse{Success: false, LatencyMs: latency, Error: err.Error()}, nil
	}
	return &ipc.TestUpstreamResponse{Success: true, LatencyMs: latency}, nil
}

func (p *program) resolveHostWithBootstrap(ctx context.Context, host string) (string, error) {
	cleanHost := strings.Trim(host, "[]")
	if cleanHost == "" || net.ParseIP(cleanHost) != nil {
		return cleanHost, nil
	}
	p.mu.Lock()
	bsCfg := p.cfg.Upstream.Bootstrap
	p.mu.Unlock()

	if !bsCfg.Enabled || len(bsCfg.Servers) == 0 {
		return cleanHost, nil
	}
	bs := core.NewBootstrapResolver(bsCfg)
	return bs.ResolveHost(ctx, cleanHost)
}

// SetAdapterTakeover 实现 ServiceController 接口
func (p *program) SetAdapterTakeover(ctx context.Context, req ipc.AdapterTakeoverRequest) error {
	if req.Enable {
		adapters, err := p.adapterScan.ScanAll(ctx)
		if err != nil {
			return err
		}
		var target *platform.AdapterInfo
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
