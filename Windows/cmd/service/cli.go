package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/haoze-evolluling/diting/windows/internal/config"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
	"github.com/kardianos/service"
)

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
		fmt.Printf("[警告] 快照自愈出现异常: %v，将继续执行全网卡兜底自愈...\n", err)
	} else if healed {
		fmt.Println("[成功] 已根据残留状态成功恢复系统网卡 DNS！")
	} else {
		fmt.Println("[提示] 未检测到残留接管状态文件。")
	}

	// 无论是否存在快照，均强制执行全网卡回环残留 (127.0.0.1 / ::1) 兜底还原至 DHCP
	if err := mgr.ResetResidualLoopbackDNS(context.Background()); err != nil {
		fmt.Printf("[警告] 全网卡兜底自愈时出现错误: %v\n", err)
	} else {
		fmt.Println("[成功] 已完成全网卡 DNS 状态排查与兜底重置（残留回环已恢复为自动获取）。")
	}
	_ = mgr.FlushDNSCache(context.Background())
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
