package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/kardianos/service"
	"github.com/miekg/dns"
)

// Version 信息（可在编译期通过 -ldflags 注入）
var (
	Version   = "0.1.0-dev"
	BuildTime = "dev"
	GitCommit = "dev"
)

// program 实现 service.Interface 接口
type program struct{}

func (p *program) Start(s service.Service) error {
	go p.run()
	return nil
}

func (p *program) run() {
	// 后续阶段在此启动 DNS 监听器与 IPC Server
}

func (p *program) Stop(s service.Service) error {
	return nil
}

func printVersion() {
	fmt.Printf("diting-service version %s (built: %s, commit: %s)\n", Version, BuildTime, GitCommit)
	fmt.Printf("DNS engine: miekg/dns (%s)\n", dns.TypeToString[dns.TypeA])
}

func main() {
	showVersion := flag.Bool("v", false, "显示服务版本号并退出")
	flag.BoolVar(showVersion, "version", false, "显示服务版本号并退出")
	serviceAction := flag.String("service", "", "控制 Windows 服务 (install, uninstall, start, stop, restart)")
	flag.Parse()

	// 若显式请求版本或未传任何参数，打印版本信息（确保 Phase 0 验证顺利）
	if *showVersion || (len(os.Args) == 1 && *serviceAction == "") {
		printVersion()
		return
	}

	svcConfig := &service.Config{
		Name:        "DitingDNSService",
		DisplayName: "谛听 DNS 内核特权服务",
		Description: "谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。",
	}

	prg := &program{}
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
