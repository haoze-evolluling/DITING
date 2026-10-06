package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/windows/internal/dns"
	"github.com/kardianos/service"
	miekgdns "github.com/miekg/dns"
)

// Version 信息（可在编译期通过 -ldflags 注入）
var (
	Version   = "0.1.0-dev"
	BuildTime = "dev"
	GitCommit = "dev"
)

// program 实现 service.Interface 接口
type program struct {
	port     int
	server   *ditingdns.Server
	resolver *core.CoreResolver
}

func (p *program) Start(s service.Service) error {
	go p.run()
	return nil
}

func (p *program) run() {
	cfg := core.ResolverConfig{
		Mode: core.ModePrimaryBackup,
		Providers: []core.ProviderConfig{
			{ID: "primary-ali", Protocol: core.ProtocolPlain, Server: "223.5.5.5:53"},
			{ID: "backup-dnspod", Protocol: core.ProtocolPlain, Server: "119.29.29.29:53"},
		},
		Bootstrap: core.BootstrapConfig{
			Enabled: true,
			Servers: []core.BootstrapServer{
				{ID: "bs-ali", Name: "AliDNS", Address: "223.5.5.5:53", Weight: 1.0},
				{ID: "bs-dnspod", Name: "DNSPod", Address: "119.29.29.29:53", Weight: 1.0},
			},
		},
	}

	res, err := core.NewResolver(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "初始化 DNS 内核失败: %v\n", err)
		return
	}
	p.resolver = res

	metricsMw := ditingdns.NewMetricsMiddleware(func(ctx *ditingdns.DNSContext, duration time.Duration, err error) {
		qName := ""
		if ctx.Req != nil && len(ctx.Req.Question) > 0 {
			qName = ctx.Req.Question[0].Name
		}
		if err != nil {
			fmt.Printf("[DNS] Query %s from %s failed (%v): %v\n", qName, ctx.ClientIP, duration, err)
		} else {
			fmt.Printf("[DNS] Query %s from %s resolved in %v\n", qName, ctx.ClientIP, duration)
		}
	})

	pipeline := ditingdns.NewPipeline(metricsMw, ditingdns.NewForwardMiddleware(res))

	port := p.port
	if port <= 0 {
		port = 53
	}

	serverCfg := ditingdns.ServerConfig{
		UDPAddresses: []string{fmt.Sprintf("127.0.0.1:%d", port), fmt.Sprintf("[::1]:%d", port)},
		TCPAddresses: []string{fmt.Sprintf("127.0.0.1:%d", port), fmt.Sprintf("[::1]:%d", port)},
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
	}

	srv := ditingdns.NewServer(serverCfg, pipeline)
	p.server = srv

	if err := srv.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "启动 DNS 双栈监听失败: %v\n", err)
		return
	}
	fmt.Printf("谛听 DNS 监听器已启动: %v (UDP/TCP)\n", serverCfg.UDPAddresses)
}

func (p *program) Stop(s service.Service) error {
	if p.server != nil {
		_ = p.server.Shutdown()
	}
	if p.resolver != nil {
		_ = p.resolver.Shutdown()
	}
	fmt.Println("谛听 DNS 监听器已优雅停止")
	return nil
}

func printVersion() {
	fmt.Printf("diting-service version %s (built: %s, commit: %s)\n", Version, BuildTime, GitCommit)
	fmt.Printf("DNS engine: miekg/dns (%s)\n", miekgdns.TypeToString[miekgdns.TypeA])
}

func main() {
	showVersion := flag.Bool("v", false, "显示服务版本号并退出")
	flag.BoolVar(showVersion, "version", false, "显示服务版本号并退出")
	serviceAction := flag.String("service", "", "控制 Windows 服务 (install, uninstall, start, stop, restart)")
	runConsole := flag.Bool("run", false, "在前台控制台直接运行 DNS 服务")
	listenPort := flag.Int("port", 53, "DNS 服务监听端口 (默认 53)")
	flag.Parse()

	// 若显式请求版本或未传任何参数且未指定运行模式，打印版本信息（确保 Phase 0 验证顺利）
	if *showVersion || (len(os.Args) == 1 && *serviceAction == "" && !*runConsole) {
		printVersion()
		return
	}

	svcConfig := &service.Config{
		Name:        "DitingDNSService",
		DisplayName: "谛听 DNS 内核特权服务",
		Description: "谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。",
	}

	prg := &program{port: *listenPort}
	s, err := service.New(prg, svcConfig)
	if err != nil {
		fmt.Fprintf(os.Stderr, "初始化 Windows 服务失败: %v\n", err)
		os.Exit(1)
	}

	if *serviceAction != "" {
		if err := service.Control(s, *serviceAction); err != nil {
			fmt.Fprintf(os.Stderr, "服务控制操作 [%s] 失败: %v\n", *serviceAction, err)
			os.Exit(1)
		}
		fmt.Printf("服务控制操作 [%s] 成功完成\n", *serviceAction)
		return
	}

	// 运行服务（支持服务模式和控制台交互模式）
	if err := s.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "服务运行失败: %v\n", err)
		os.Exit(1)
	}
}
