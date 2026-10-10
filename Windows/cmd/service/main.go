package main

import (
	"context"
	"fmt"
	"io/fs"
	"log"
	"net"
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
)

// Version 信息（可在编译期通过 -ldflags 注入）
var (
	Version   = "1.3.3"
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
		go func(pt int) {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := windows.ConfigureFirewallPortWeb(ctx, executor, pt, true); err != nil {
				log.Printf("[防火墙] 同步 Web 端口入站规则警告: %v\n", err)
			}
		}(port)
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
