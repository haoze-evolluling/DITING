package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

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
	Version   = "1.2.10"
	BuildTime = "dev"
	GitCommit = "dev"
)

type program struct {
	configPath string
	dnsPort    int
	ipcAddr    string
	token      string

	cfg         *config.Config
	server      *ditingdns.Server
	resolver     *core.CoreResolver
	cache        *core.DNSCache
	filterEngine *core.RuleEngine
	takeoverMgr  windows.DNSManager
	adapterScan windows.AdapterScanner
	stateStore  windows.StateStore
	portChecker windows.PortChecker
	ipcServer   *ipc.Server

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

	// 6. 初始化 IPC 服务
	p.ipcServer = ipc.NewServer(cfg.IPC.ListenAddress, cfg.IPC.AuthToken, p)
	if err := p.ipcServer.Start(); err != nil {
		return fmt.Errorf("启动 IPC 本地服务失败: %w", err)
	}
	log.Printf("[IPC] 本地服务已启动于: %s (Token鉴权: %v)\n", p.ipcServer.Addr(), cfg.IPC.AuthToken != "")

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
	serverCfg := ditingdns.ServerConfig{
		UDPAddresses: p.cfg.DNS.UDPAddresses,
		TCPAddresses: p.cfg.DNS.TCPAddresses,
		ReadTimeout:  p.cfg.DNS.ReadTimeout,
		WriteTimeout: p.cfg.DNS.WriteTimeout,
	}

	// 53 端口占用前置检测：若本地监听端口已被外部进程或服务占用，立即执行深度冲突诊断
	if p.portChecker != nil && !windows.IsPort53Available() {
		res, checkErr := p.portChecker.CheckPort53(ctx)
		if checkErr == nil && !res.Available {
			return &windows.PortConflictError{Result: res}
		}
	}

	srv := ditingdns.NewServer(serverCfg, pipeline)
	if err := srv.Start(); err != nil {
		if p.portChecker != nil && windows.IsPortBindConflict(err) {
			res, checkErr := p.portChecker.CheckPort53(ctx)
			if checkErr == nil && res != nil {
				return &windows.PortConflictError{Result: res, Err: err}
			}
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
	return &ipc.StatusResponse{
		Version:       Version,
		PID:           os.Getpid(),
		UptimeSeconds: int64(time.Since(p.startTime).Seconds()),
		DNS: ipc.DNSStatus{
			Running:         dnsRun,
			ListenAddresses: p.cfg.DNS.UDPAddresses,
			Mode:            p.cfg.Upstream.Mode,
			Upstreams:       upstreams,
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

func printVersion() {
	fmt.Printf("diting-service version %s (built: %s, commit: %s)\n", Version, BuildTime, GitCommit)
	fmt.Println("DNS engine: miekg/dns | Platform: Windows | IPC: HTTP/WebSocket")
}

func executeEmergencyRestore(customConfigPath string) {
	fmt.Println("[谛听] 正在执行独立离线 DNS 紧急恢复...")
	statePath := ""
	if customConfigPath != "" {
		if cfg, err := config.LoadConfig(customConfigPath); err == nil {
			statePath = cfg.Takeover.StateFilePath
		}
	}
	store := windows.NewFileStateStore(statePath)
	exec := windows.NewDefaultExecutor()
	mgr := windows.NewDNSManager(exec, store, Version)
	healed, err := store.CheckAndSelfHeal(context.Background(), mgr)
	if err != nil {
		fmt.Printf("[失败] 恢复失败: %v\n", err)
		os.Exit(1)
	}
	if healed {
		fmt.Println("[成功] 已根据残留状态成功恢复系统网卡 DNS！")
	} else {
		fmt.Println("[提示] 未检测到残留接管状态文件，系统网卡 DNS 处于正常状态。")
	}
}

func executePortDiagnostics() {
	fmt.Println("[谛听] 正在探测本地 53 端口占用与冲突...")
	checker := windows.NewPortChecker(nil)
	res, err := checker.CheckPort53(context.Background())
	if err != nil {
		fmt.Printf("[错误] 探测失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("端口 127.0.0.1:53 绑定可用性: %v\n", res.Available)
	fmt.Printf("是否检测到 ICS (SharedAccess): %v\n", res.HasICS)
	fmt.Println("--------------------------------------------------")
	fmt.Printf("诊断报告:\n%s\n", res.Diagnostic)
	fmt.Println("--------------------------------------------------")
	if len(res.Conflicts) > 0 {
		fmt.Println("现存 53 端口监听实体:")
		for i, c := range res.Conflicts {
			fmt.Printf("  [%d] %s %s (PID: %d, 进程: %s, ICS: %v, 自身: %v)\n", i+1, c.Protocol, c.LocalAddress, c.PID, c.ProcessName, c.IsICS, c.IsSelf)
		}
	}
}

func main() {
	showVersion := flag.Bool("v", false, "显示服务版本号并退出")
	flag.BoolVar(showVersion, "version", false, "显示服务版本号并退出")
	serviceAction := flag.String("service", "", "控制 Windows 服务 (install, uninstall, start, stop, restart)")
	runConsole := flag.Bool("run", false, "在前台控制台直接运行 DNS 服务")
	listenPort := flag.Int("port", 0, "DNS 服务监听端口 (默认从配置读取或 53)")
	ipcAddr := flag.String("ipc-addr", "", "IPC HTTP/WS 监听地址 (默认 127.0.0.1:15353)")
	token := flag.String("token", "", "IPC 访问鉴权 Token")
	configPath := flag.String("config", "", "配置文件绝对路径")
	checkPorts := flag.Bool("check-ports", false, "独立诊断 53 端口冲突并退出")
	emergencyRestore := flag.Bool("restore", false, "独立恢复残留的系统 DNS 设置并退出")
	flag.Parse()

	if *showVersion || (service.Interactive() && len(os.Args) == 1 && *serviceAction == "" && !*runConsole && !*checkPorts && !*emergencyRestore) {
		printVersion()
		return
	}

	if *checkPorts {
		executePortDiagnostics()
		return
	}

	if *emergencyRestore {
		executeEmergencyRestore(*configPath)
		return
	}

	svcConfig := &service.Config{
		Name:        "DitingDNSService",
		DisplayName: "谛听 DNS 内核特权服务",
		Description: "谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。",
		Arguments:   []string{"-run"},
	}
	if *configPath != "" {
		absPath, _ := filepath.Abs(*configPath)
		svcConfig.Arguments = append(svcConfig.Arguments, "-config", absPath)
	}
	if *listenPort > 0 {
		svcConfig.Arguments = append(svcConfig.Arguments, "-port", fmt.Sprintf("%d", *listenPort))
	}
	if *ipcAddr != "" {
		svcConfig.Arguments = append(svcConfig.Arguments, "-ipc-addr", *ipcAddr)
	}
	if *token != "" {
		svcConfig.Arguments = append(svcConfig.Arguments, "-token", *token)
	}

	prg := &program{
		configPath: *configPath,
		dnsPort:    *listenPort,
		ipcAddr:    *ipcAddr,
		token:      *token,
	}

	s, err := service.New(prg, svcConfig)
	if err != nil {
		log.Fatalf("初始化 Windows 服务失败: %v\n", err)
	}

	if *serviceAction != "" {
		if err := service.Control(s, *serviceAction); err != nil {
			log.Fatalf("服务控制操作 [%s] 失败: %v\n", *serviceAction, err)
		}
		fmt.Printf("服务控制操作 [%s] 成功完成\n", *serviceAction)
		return
	}

	if err := s.Run(); err != nil {
		log.Fatalf("服务运行失败: %v\n", err)
	}
}
