package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/windows/frontend"
	"github.com/haoze-evolluling/diting/windows/internal/auth"
	"github.com/haoze-evolluling/diting/windows/internal/config"
	"github.com/haoze-evolluling/diting/windows/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/windows/internal/dns"
	"github.com/haoze-evolluling/diting/windows/internal/ipc"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
	"github.com/kardianos/service"
	miekgdns "github.com/miekg/dns"
)

// Version 信息（可在编译期通过 -ldflags 注入）
var (
	Version   = "1.3.1"
	BuildTime = "dev"
	GitCommit = "dev"
)

type program struct {
	configPath string
	dnsPort    int
	ipcAddr    string
	token      string

	cfg          *config.Config
	server       *ditingdns.Server
	resolver     *core.CoreResolver
	cache        *core.DNSCache
	filterEngine *core.RuleEngine
	takeoverMgr  windows.DNSManager
	adapterScan  windows.AdapterScanner
	stateStore   windows.StateStore
	portChecker  windows.PortChecker
	ipcServer    *ipc.Server
	authMgr      *auth.Manager

	startTime time.Time
	metrics   *metricsTracker

	mu         sync.Mutex
	dnsRunning bool
	stopped    chan struct{}
}

func (p *program) Start(s service.Service) error {
	p.startTime = time.Now()
	p.metrics = newMetricsTracker()
	p.stopped = make(chan struct{})

	go func() {
		if err := p.run(); err != nil {
			log.Printf("[错误] 服务运行异常: %v\n", err)
		}
	}()
	return nil
}

func (p *program) run() error {
	// 1. 加载配置
	cfg, err := config.LoadConfig(p.configPath)
	if err != nil {
		log.Printf("[配置] 加载配置失败，使用默认配置: %v\n", err)
		cfg = config.DefaultConfig()
	}
	if p.dnsPort > 0 {
		cfg.DNS.UDPAddresses = []string{fmt.Sprintf("127.0.0.1:%d", p.dnsPort), fmt.Sprintf("[::1]:%d", p.dnsPort)}
		cfg.DNS.TCPAddresses = []string{fmt.Sprintf("127.0.0.1:%d", p.dnsPort), fmt.Sprintf("[::1]:%d", p.dnsPort)}
	}
	if p.ipcAddr != "" {
		cfg.IPC.ListenAddress = p.ipcAddr
	}
	if p.token != "" {
		cfg.IPC.AuthToken = p.token
	}
	p.cfg = cfg

	// 2. 初始化平台能力模块
	executor := windows.NewDefaultExecutor()
	p.stateStore = windows.NewFileStateStore(cfg.Takeover.StateFilePath)
	p.takeoverMgr = windows.NewDNSManager(executor, p.stateStore, Version)
	p.adapterScan = windows.NewAdapterScanner(executor)
	p.portChecker = windows.NewPortChecker(executor)

	// 3. 执行崩溃自愈与残留检查
	healed, err := p.stateStore.CheckAndSelfHeal(context.Background(), p.takeoverMgr)
	if err != nil {
		log.Printf("[自愈检查] 异常: %v\n", err)
	} else if healed {
		log.Printf("[自愈检查] 检测到上次非正常退出残留的接管状态，已成功执行自愈还原！\n")
	}

	// 4. 探测 53 端口冲突与 ICS 状态
	portCheck, err := p.portChecker.CheckPort53(context.Background())
	if err != nil {
		log.Printf("[端口探测] 失败: %v\n", err)
	} else {
		if portCheck.HasICS {
			log.Printf("[端口探测警告] 检测到 SharedAccess (ICS) 服务运行中！\n%s\n", portCheck.Diagnostic)
		} else if !portCheck.Available {
			log.Printf("[端口探测提醒] 127.0.0.1:53 可能存在冲突: %s\n", portCheck.Diagnostic)
		}
	}

	// 5. 初始化纯 Go 核心解析器与智能缓存体系
	res, err := core.NewResolver(cfg.Upstream)
	if err != nil {
		return fmt.Errorf("初始化 DNS 核心内核失败: %w", err)
	}
	p.resolver = res
	p.cache = core.NewDNSCache(cfg.Cache)
	p.filterEngine = core.NewRuleEngine(cfg.Filter)

	// 5.1 初始化 Web 远程管理与认证引擎
	p.authMgr = auth.NewManager(cfg.Web.Username, cfg.Web.PasswordHash, cfg.Web.Salt, cfg.Web.SessionTimeout)

	// 6. 初始化 IPC / Web 静态服务
	ipcListen := cfg.IPC.ListenAddress
	if cfg.Web.Enabled {
		port := p.effectiveWebPort()
		ipcListen = fmt.Sprintf("0.0.0.0:%d", port)
		p.cfg.IPC.ListenAddress = ipcListen
	}
	p.ipcServer = ipc.NewServer(ipcListen, cfg.IPC.AuthToken, p)
	p.initAssetsForServer(p.ipcServer)
	if err := p.ipcServer.Start(); err != nil {
		return fmt.Errorf("启动 IPC 本地服务失败: %w", err)
	}
	log.Printf("[IPC/Web] 服务已启动于: %s (局域网Web: %v, Token鉴权: %v)\n", p.ipcServer.Addr(), cfg.Web.Enabled, cfg.IPC.AuthToken != "")

	// 7. 启动本地 DNS 监听器
	if err := p.StartDNS(context.Background()); err != nil {
		log.Printf("[DNS] 启动监听器失败: %v\n", err)
	}

	// 8. 检查自动接管选项
	if cfg.Takeover.AutoTakeoverOnStart {
		if err := p.EnableTakeover(context.Background()); err != nil {
			log.Printf("[接管] 自动接管失败: %v\n", err)
		}
	}

	// 9. 启动定时指标推送协程
	go p.runMetricsTicker()

	<-p.stopped
	return nil
}

func (p *program) runMetricsTicker() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-p.stopped:
			return
		case <-ticker.C:
			if p.ipcServer != nil {
				snapshot := p.metrics.Snapshot()
				p.ipcServer.Broadcast(ipc.Event{
					Type:      "metrics",
					Timestamp: time.Now().UnixMilli(),
					Data:      snapshot,
				})
			}
		}
	}
}

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
	if needs53 && p.portChecker != nil && !windows.IsPort53Available() {
		res, checkErr := p.portChecker.CheckPort53(ctx)
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
				if res, checkErr := p.portChecker.CheckPort53(ctx); checkErr == nil && res != nil {
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

// CheckPortConflicts 实现 ServiceController 接口
func (p *program) CheckPortConflicts(ctx context.Context) (*windows.PortCheckResult, error) {
	return p.portChecker.CheckPort53(ctx)
}

func fallbackPortConflict(err error) *windows.PortConflictError {
	return &windows.PortConflictError{
		Result: &windows.PortCheckResult{
			Available:  false,
			Diagnostic: "本地 53 端口已被占用，无法启动 DNS 监听器。排查建议：请检查是否有其他 DNS 或代理软件占用该端口。",
		},
		Err: err,
	}
}

func (p *program) Stop(s service.Service) error {
	log.Println("[服务] 收到停止信号，执行优雅退出...")

	// 优先恢复网卡 DNS
	if p.takeoverMgr != nil && p.takeoverMgr.IsTakeoverActive() {
		log.Println("[服务] 正在安全还原网卡 DNS...")
		_ = p.takeoverMgr.Restore(context.Background())
	}

	if p.filterEngine != nil {
		p.filterEngine.Close()
	}

	_ = p.StopDNS(context.Background())

	if p.cache != nil {
		p.cache.Close()
	}
	if p.ipcServer != nil {
		_ = p.ipcServer.Shutdown(context.Background())
	}
	if p.resolver != nil {
		_ = p.resolver.Shutdown()
	}

	select {
	case <-p.stopped:
	default:
		close(p.stopped)
	}
	return nil
}

func formatIP(ip net.IP) string {
	if ip == nil {
		return ""
	}
	return ip.String()
}

func (p *program) initAssetsForServer(srv *ipc.Server) {
	if srv == nil {
		return
	}
	if sub, err := fs.Sub(frontend.Assets, "dist"); err == nil {
		srv.SetAssetsFS(sub)
	}
}

