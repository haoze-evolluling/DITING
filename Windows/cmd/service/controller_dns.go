package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/windows/internal/dns"
	"github.com/haoze-evolluling/diting/windows/internal/ipc"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
	miekgdns "github.com/miekg/dns"
)

// StartDNS 实现 ServiceController 接口
func (p *program) StartDNS(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.dnsRunning {
		return nil
	}

	metricsMw := ditingdns.NewMetricsMiddleware(func(dctx *ditingdns.DNSContext, duration time.Duration, err error) {
		qName := ""
		qType := ""
		if dctx.Req != nil && len(dctx.Req.Question) > 0 {
			qName = dctx.Req.Question[0].Name
			qType = miekgdns.TypeToString[dctx.Req.Question[0].Qtype]
		}
		success := (err == nil)
		p.metrics.RecordQuery(duration, success)

		cacheHitStr := ""
		if val, ok := dctx.Get("cache_hit"); ok {
			if s, ok := val.(string); ok {
				cacheHitStr = s
			}
		}
		rcodeStr := ""
		if dctx.Resp != nil {
			rcodeStr = miekgdns.RcodeToString[dctx.Resp.Rcode]
		}

		filterBlocked := false
		filterRule := ""
		filterReason := ""
		if val, ok := dctx.Get("filter_blocked"); ok {
			if b, ok := val.(bool); ok {
				filterBlocked = b
			}
		}
		if val, ok := dctx.Get("filter_rule"); ok {
			if s, ok := val.(string); ok {
				filterRule = s
			}
		}
		if val, ok := dctx.Get("filter_reason"); ok {
			if s, ok := val.(string); ok {
				filterReason = s
			}
		}

		if p.ipcServer != nil {
			errStr := ""
			if err != nil {
				errStr = err.Error()
			}
			p.ipcServer.Broadcast(ipc.Event{
				Type:      "query",
				Timestamp: time.Now().UnixMilli(),
				Data: ipc.QueryEventData{
					Domain:       qName,
					QType:        qType,
					ClientIP:     formatIP(dctx.ClientIP),
					DurationMs:   float64(duration.Nanoseconds()) / 1e6,
					Success:      success,
					RCode:        rcodeStr,
					CacheHit:     cacheHitStr,
					Blocked:      filterBlocked,
					FilterRule:   filterRule,
					FilterReason: filterReason,
					ErrorMessage: errStr,
				},
			})
		}
	})

	filterMw := ditingdns.NewFilterMiddleware(p.filterEngine)
	cacheMw := ditingdns.NewCacheMiddleware(p.cache, p.resolver)
	pipeline := ditingdns.NewPipeline(metricsMw, filterMw, cacheMw, ditingdns.NewForwardMiddleware(p.resolver))
	udpAddrs, tcpAddrs := p.cfg.DNS.EffectiveListenAddresses()
	serverCfg := ditingdns.ServerConfig{
		UDPAddresses: udpAddrs,
		TCPAddresses: tcpAddrs,
		ReadTimeout:  p.cfg.DNS.ReadTimeout,
		WriteTimeout: p.cfg.DNS.WriteTimeout,
	}

	// 53 端口占用前置检测：若本地监听包含 53 且不可用，立即执行深度冲突诊断
	needs53 := false
	for _, a := range append(serverCfg.UDPAddresses, serverCfg.TCPAddresses...) {
		if strings.HasSuffix(a, ":53") {
			needs53 = true
			break
		}
	}
	if needs53 && p.portChecker != nil && !windows.AreAddressesAvailable(serverCfg.UDPAddresses, serverCfg.TCPAddresses) {
		res, checkErr := p.portChecker.CheckPort53ForAddresses(ctx, serverCfg.UDPAddresses, serverCfg.TCPAddresses)
		if checkErr == nil && res != nil && !res.Available {
			return &windows.PortConflictError{Result: res}
		}
		if checkErr != nil {
			return fallbackPortConflict(nil)
		}
	}

	srv := ditingdns.NewServer(serverCfg, pipeline)
	if err := srv.Start(); err != nil {
		if windows.IsPortBindConflict(err) {
			if p.portChecker != nil {
				if res, checkErr := p.portChecker.CheckPort53ForAddresses(ctx, serverCfg.UDPAddresses, serverCfg.TCPAddresses); checkErr == nil && res != nil {
					return &windows.PortConflictError{Result: res, Err: err}
				}
			}
			return fallbackPortConflict(err)
		}
		return fmt.Errorf("启动 DNS 监听器失败: %w", err)
	}

	p.server = srv
	p.dnsRunning = true
	log.Printf("[DNS] 谛听 DNS 监听器已就绪: %v\n", serverCfg.UDPAddresses)
	return nil
}

// StopDNS 实现 ServiceController 接口
func (p *program) StopDNS(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if !p.dnsRunning {
		return nil
	}

	// 关键保护：若当前处于系统 DNS 接管状态，必须先安全还原网卡，防止系统网络彻底断连
	if p.takeoverMgr != nil && p.takeoverMgr.IsTakeoverActive() {
		log.Println("[DNS] 停止 DNS 监听前检测到接管生效中，自动先还原系统 DNS 接管...")
		if err := p.takeoverMgr.Restore(ctx); err != nil {
			log.Printf("[DNS警告] 自动还原系统 DNS 接管失败: %v\n", err)
		} else if p.ipcServer != nil {
			p.ipcServer.Broadcast(ipc.Event{Type: "takeover", Timestamp: time.Now().UnixMilli(), Data: "disabled"})
		}
	}

	if p.server != nil {
		_ = p.server.Shutdown()
		p.server = nil
	}
	p.dnsRunning = false
	log.Println("[DNS] 谛听 DNS 监听器已停止")
	return nil
}

// EnableTakeover 实现 ServiceController 接口
func (p *program) EnableTakeover(ctx context.Context) error {
	p.mu.Lock()
	dnsRun := p.dnsRunning
	p.mu.Unlock()

	if !dnsRun {
		log.Println("[接管] DNS 服务未处于运行状态，自动先启动本地 DNS 监听器...")
		if err := p.StartDNS(ctx); err != nil {
			var pErr *windows.PortConflictError
			if errors.As(err, &pErr) {
				return pErr
			}
			return fmt.Errorf("接管前启动 DNS 监听器失败: %w", err)
		}
	}

	adapters, err := p.adapterScan.GetActivePhysicalAdapters(ctx)
	if err != nil {
		return fmt.Errorf("枚举活动物理网卡失败: %w", err)
	}
	if len(adapters) == 0 {
		return fmt.Errorf("未检测到有效活动的物理网卡（以太网或 Wi-Fi）")
	}

	if err := p.takeoverMgr.Takeover(ctx, adapters); err != nil {
		return err
	}
	log.Printf("[接管] 已成功接管 %d 个活动物理网卡\n", len(adapters))
	return nil
}

// DisableTakeover 实现 ServiceController 接口
func (p *program) DisableTakeover(ctx context.Context) error {
	if err := p.takeoverMgr.Restore(ctx); err != nil {
		return err
	}
	log.Println("[接管] 已成功还原物理网卡 DNS 设置")
	return nil
}

// GetAdapters 实现 ServiceController 接口
func (p *program) GetAdapters(ctx context.Context) ([]windows.AdapterInfo, error) {
	if p.adapterScan == nil {
		p.adapterScan = windows.NewAdapterScanner(windows.NewDefaultExecutor())
	}
	return p.adapterScan.ScanAll(ctx)
}

// GetStatus 实现 ServiceController 接口
func (p *program) GetStatus(ctx context.Context) (*ipc.StatusResponse, error) {
	p.mu.Lock()
	dnsRun := p.dnsRunning
	p.mu.Unlock()

	upstreams := make([]ipc.UpstreamInfo, 0)
	if p.resolver != nil {
		stats := p.resolver.GetProviderStats()
		for _, stat := range stats {
			upstreams = append(upstreams, ipc.UpstreamInfo{
				ID:           stat.ID,
				Protocol:     string(stat.Protocol),
				Server:       stat.Server,
				URL:          stat.URL,
				Active:       stat.IsHealthy,
				SuccessCount: stat.SuccessCount,
				FailureCount: stat.FailureCount,
				AvgLatencyMs: stat.AvgLatencyMs,
			})
		}
	}

	takenAdapters := p.takeoverMgr.GetTakenOverAdapters()
	lanAddrs, _ := windows.GetLANAddresses()
	effUDP, _ := p.cfg.DNS.EffectiveListenAddresses()
	return &ipc.StatusResponse{
		Version:       Version,
		PID:           os.Getpid(),
		UptimeSeconds: int64(time.Since(p.startTime).Seconds()),
		DNS: ipc.DNSStatus{
			Running:         dnsRun,
			ListenAddresses: effUDP,
			AllowLAN:        p.cfg.DNS.AllowLAN,
			LANAddresses:    lanAddrs,
			Mode:            p.cfg.Upstream.Mode,
			Upstreams:       upstreams,
			Bootstrap:       p.cfg.Upstream.Bootstrap,
		},
		Takeover: ipc.TakeoverStatus{
			Active:   p.takeoverMgr.IsTakeoverActive(),
			Adapters: takenAdapters,
		},
		Metrics: p.metrics.Snapshot(),
		Cache:   p.getCacheStatsSnapshot(),
		Filter:  p.getFilterStatsSnapshot(),
	}, nil
}

func (p *program) getCacheStatsSnapshot() core.CacheStats {
	if p.cache != nil {
		return p.cache.Stats()
	}
	return core.CacheStats{Enabled: false}
}

func (p *program) getFilterStatsSnapshot() core.FilterStats {
	if p.filterEngine != nil {
		return p.filterEngine.GetStats()
	}
	return core.FilterStats{Enabled: false}
}
