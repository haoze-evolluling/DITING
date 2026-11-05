package main

import (
	"context"
	"fmt"
	"io/fs"
	"log"
	"net"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/server/frontend"
	"github.com/haoze-evolluling/diting/server/internal/auth"
	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/server/internal/dns"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/platform"
	"github.com/haoze-evolluling/diting/server/internal/querylog"
	"github.com/kardianos/service"
)

// Version 信息（可在编译期通过 -ldflags 注入）
var (
	Version   = "2.2.11"
	BuildTime = "dev"
	GitCommit = "dev"
)

type program struct {
	configPath string
	dnsPort    int
	ipcAddr    string
	token      string

	cfg            *config.Config
	server         *ditingdns.Server
	resolver       *core.CoreResolver
	cache          *core.DNSCache
	queryLog       *querylog.QueryLog
	filterEngine   *core.RuleEngine
	groupResolver  *core.GroupResolver
	hostsResolver  *core.HostsResolver
	rebindMgr      *ditingdns.RebindProtectionManager
	accessControl  *core.AccessControl
	rateLimiter    *core.RateLimiter
	dns64Synth     *core.DNS64Synthesizer
	rewriteEngine  *core.RewriteEngine
	zoneEngine     *core.ZoneEngine
	safeSearchEng  *core.SafeSearchEngine
	safeBrowsing   *core.SafeBrowsingEngine
	certManager    *core.CertManager
	clientResolver *core.ClientResolver
	ecsMgr         *ditingdns.ECSManager
	takeoverMgr    platform.DNSManager
	adapterScan    platform.AdapterScanner
	stateStore     platform.StateStore
	portChecker    platform.PortChecker
	ipcServer      *ipc.Server
	authMgr        *auth.Manager
	serviceMgr     platform.ServiceManager

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
	if p.configPath == "" {
		p.configPath = config.GetDefaultConfigPath()
	}
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
	executor := platform.NewDefaultExecutor()
	p.stateStore = platform.NewFileStateStore(cfg.Takeover.StateFilePath)
	p.takeoverMgr = newDNSManager(executor, p.stateStore, Version)
	p.adapterScan = newAdapterScanner(executor)
	p.portChecker = newPortChecker(executor)
	p.serviceMgr = newServiceManager(executor)

	// 3. 执行崩溃自愈与残留检查
	healed, err := p.stateStore.CheckAndSelfHeal(context.Background(), p.takeoverMgr)
	if err != nil {
		log.Printf("[自愈检查] 异常: %v\n", err)
	} else if healed {
		log.Printf("[自愈检查] 检测到上次非正常退出残留的接管状态，已成功执行自愈还原！\n")
	}

	// 4. 探测 53 端口冲突与系统级占用（Windows ICS / Linux systemd-resolved stub）
	portCheck, err := p.portChecker.CheckPort53(context.Background())
	if err != nil {
		log.Printf("[端口探测] 失败: %v\n", err)
	} else {
		if portCheck.HasICS {
			log.Printf("[端口探测警告] 检测到系统级 53 端口占用（Windows ICS / Linux systemd-resolved stub）！\n%s\n", portCheck.Diagnostic)
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
	p.cache.SetPrefetcher(res)
	p.restoreCacheFromDisk()
	p.queryLog = querylog.New(cfg.QueryLog)
	p.filterEngine = core.NewRuleEngine(cfg.Filter)
	if err := p.filterEngine.SetClientGroups(cfg.Client.GroupConfig()); err != nil {
		log.Printf("[Clients] 载入客户端分组警告: %v\n", err)
	}
	clientGroupCfg := cfg.Client.GroupConfig()
	if gr, err := core.NewGroupResolver(clientGroupCfg); err == nil {
		p.groupResolver = gr
	} else {
		log.Printf("[Clients] 编译客户端分组匹配器警告: %v\n", err)
	}
	// 分组专属上游依赖已装配的主链路，故须在两个前置件就绪之后绑定
	p.applyGroupUpstreams(clientGroupCfg)

	hostsRes, err := core.NewHostsResolver(cfg.Hosts)
	if err != nil {
		log.Printf("[Hosts] 初始化 Hosts 解析器警告: %v\n", err)
	}
	p.hostsResolver = hostsRes
	p.rebindMgr = ditingdns.NewRebindProtectionManager(cfg.Rebind)

	accessCtrl, err := core.NewAccessControl(cfg.Access)
	if err != nil {
		log.Printf("[Access] 初始化访问控制警告: %v\n", err)
	}
	p.accessControl = accessCtrl
	p.rateLimiter = core.NewRateLimiter(context.Background(), cfg.RateLimit)
	dns64Synth, err := core.NewDNS64Synthesizer(cfg.DNS64)
	if err != nil {
		log.Printf("[DNS64] 初始化 DNS64 合成器警告: %v\n", err)
	}
	p.dns64Synth = dns64Synth
	p.rewriteEngine = core.NewRewriteEngine(cfg.Rewrite)
	p.zoneEngine = core.NewZoneEngine(cfg.Zone)
	p.safeSearchEng = core.NewSafeSearchEngine(cfg.SafeSearch)
	// 声誉查询要向上游发 TXT 问询，解析器此时已就绪
	p.safeBrowsing = core.NewSafeBrowsingEngine(cfg.SafeBrowsing, res)

	// 加密 DNS 服务端证书：自签来源在首次启动时补齐一张，
	// 其余来源直接按配置路径载入。载入失败不阻断启动——
	// 证书问题只影响加密监听器，主解析链路与它无关。
	p.certManager = core.NewCertManager(platform.DefaultCertDir(), cfg.Encrypted.Cert)
	if cfg.Encrypted.Cert.Source == core.CertSourceSelfSigned || cfg.Encrypted.Cert.Source == "" {
		certCfg := cfg.Encrypted.Cert
		if len(certCfg.DNSNames) == 0 && len(certCfg.IPAddresses) == 0 {
			certCfg.DNSNames, certCfg.IPAddresses = core.DeriveCertNames(
				cfg.Encrypted.ServerName, cfg.Encrypted.ListenAddress, nil)
		}
		// 续签而非仅补齐：证书到期后客户端握手全部失败，而本端监听器
		// 不会因此报错，只能在启动时主动换掉将到期的自签证书。
		if created, err := p.certManager.RenewSelfSignedIfNeeded(certCfg); err != nil {
			log.Printf("[加密DNS] 自签证书生成/续签失败: %v\n", err)
		} else if created {
			log.Printf("[加密DNS] 已生成/续签自签证书至 %s\n", platform.DefaultCertDir())
		}
	}
	p.clientResolver = core.NewClientResolver(cfg.Client, p.hostsResolver, p.rewriteEngine)
	p.ecsMgr = ditingdns.NewECSManager(cfg.ECS)

	// 5.1 初始化 Web 远程管理与认证引擎
	p.authMgr = auth.NewManager(cfg.Web.Username, cfg.Web.PasswordHash, cfg.Web.Salt, cfg.Web.SessionTimeout)

	// 6. 初始化 IPC / Web 静态服务
	ipcListen := cfg.IPC.ListenAddress
	if cfg.Web.Enabled {
		port := p.effectiveWebPort()
		ipcListen = fmt.Sprintf("0.0.0.0:%d", port)
		p.cfg.IPC.ListenAddress = ipcListen
		// 仅在存在防火墙后端时同步放行规则；无防火墙时端口本就开放，静默跳过
		if firewallBackendName() != "none" {
			go func(pt int) {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				if err := firewallConfigureWeb(ctx, pt, true); err != nil {
					log.Printf("[防火墙] 同步 Web 端口入站规则警告: %v\n", err)
				}
			}(port)
		}
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

// currentIPCServer 在锁内读取 IPC 服务实例。
//
// p.ipcServer 会被 ConfigureWeb 整体替换（Web 平滑重启），而 DNS 热路径、
// 定时广播与停机路径都要读它。约定与 p.cfg 一致：读该字段必须持 p.mu。
func (p *program) currentIPCServer() *ipc.Server {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ipcServer
}

func (p *program) runMetricsTicker() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-p.stopped:
			return
		case <-ticker.C:
			if srv := p.currentIPCServer(); srv != nil {
				snapshot := p.metrics.Snapshot()
				srv.Broadcast(ipc.Event{
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

	// 查询日志落盘写入器优先收尾，确保缓冲数据不丢失
	if p.queryLog != nil {
		_ = p.queryLog.Close()
	}

	if p.cache != nil {
		p.cache.Close()
	}
	if srv := p.currentIPCServer(); srv != nil {
		_ = srv.Shutdown(context.Background())
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
