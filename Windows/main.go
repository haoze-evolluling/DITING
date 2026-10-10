package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/haoze-evolluling/diting/windows/frontend"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"golang.org/x/sys/windows/registry"
)

// Version 信息
var (
	Version   = "1.3.3"
	BuildTime = "dev"
	GitCommit = "dev"
)

// App 结构体
type App struct {
	ctx        context.Context
	serviceMgr *windows.ServiceManager
}

// NewApp 构造函数
func NewApp() *App {
	return &App{
		serviceMgr: windows.NewServiceManager(nil, nil),
	}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// Greet 测试方法
func (a *App) Greet(name string) string {
	return fmt.Sprintf("Hello %s, 来自谛听 (DITING) Windows GUI!", name)
}

// CaptureWindow 截取当前客户端自身窗口界面并保存为 PNG 图像文件
func (a *App) CaptureWindow(outputPath string) (string, error) {
	return windows.CaptureDitingWindow(outputPath)
}

// RunEmergencyRestore 执行离线应急恢复
func (a *App) RunEmergencyRestore() (string, error) {
	store := windows.NewFileStateStore("")
	exec := windows.NewDefaultExecutor()
	mgr := windows.NewDNSManager(exec, store, Version)
	healed, err := store.CheckAndSelfHeal(context.Background(), mgr)
	if err != nil {
		return "", fmt.Errorf("应急恢复失败: %w", err)
	}
	if healed {
		return "已成功恢复网络 DNS 设置！", nil
	}
	return "网络 DNS 状态正常，无需修复。", nil
}

// IsAutoStartEnabled 获取当前是否已开启开机自启
func (a *App) IsAutoStartEnabled() bool {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()
	_, _, err = k.GetStringValue("DitingDNS")
	return err == nil
}

// SetAutoStart 设置或取消开机自启
func (a *App) SetAutoStart(enable bool) (bool, error) {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE)
	if err != nil {
		return false, fmt.Errorf("访问注册表失败: %w", err)
	}
	defer k.Close()

	if enable {
		exePath, err := os.Executable()
		if err != nil {
			return false, fmt.Errorf("获取执行路径失败: %w", err)
		}
		if err := k.SetStringValue("DitingDNS", `"`+exePath+`"`); err != nil {
			return false, fmt.Errorf("写入自启注册表失败: %w", err)
		}
		return true, nil
	}

	_ = k.DeleteValue("DitingDNS")
	return false, nil
}

// GetCoreServiceStatus 获取后台核心服务状态
func (a *App) GetCoreServiceStatus() (*windows.CoreServiceStatus, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	return a.serviceMgr.GetStatus(context.Background())
}

// StartCoreService 按需提权启动后台核心服务
func (a *App) StartCoreService() (string, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	if err := a.serviceMgr.StartService(context.Background()); err != nil {
		return "", err
	}
	return "后台核心服务已成功启动！", nil
}

// StopCoreService 按需提权停止后台核心服务
func (a *App) StopCoreService() (string, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	if err := a.serviceMgr.StopService(context.Background()); err != nil {
		return "", err
	}
	return "后台核心服务已停止。", nil
}

// RestartCoreService 按需提权重启后台核心服务
func (a *App) RestartCoreService() (string, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	if err := a.serviceMgr.RestartService(context.Background()); err != nil {
		return "", err
	}
	return "后台核心服务已成功重启！", nil
}

// InstallCoreService 按需提权安装注册后台核心服务
func (a *App) InstallCoreService() (string, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	if err := a.serviceMgr.InstallService(context.Background(), ""); err != nil {
		return "", err
	}
	return "后台核心服务已成功安装注册为系统服务！", nil
}

// InstallAndStartCoreService 按需提权一键安装并启动后台核心服务（单次 UAC 授权）
func (a *App) InstallAndStartCoreService() (string, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	if err := a.serviceMgr.InstallAndStartService(context.Background(), ""); err != nil {
		return "", err
	}
	return "后台核心服务已成功安装并启动！", nil
}

// UninstallCoreService 按需提权卸载注销后台核心服务
func (a *App) UninstallCoreService() (string, error) {
	if a.serviceMgr == nil {
		a.serviceMgr = windows.NewServiceManager(nil, nil)
	}
	if err := a.serviceMgr.UninstallService(context.Background()); err != nil {
		return "", err
	}
	return "后台核心服务已成功卸载。", nil
}

// ConfigureFirewallForLAN 按需配置局域网 53 端口 Windows 防火墙规则
func (a *App) ConfigureFirewallForLAN(enable bool) (string, error) {
	err := windows.ConfigureFirewallPort53(context.Background(), windows.NewDefaultExecutor(), enable)
	if err != nil {
		return "", fmt.Errorf("配置防火墙规则失败: %w", err)
	}
	if enable {
		return "已成功放行局域网 53 端口防火墙入站规则！", nil
	}
	return "已成功清除局域网 53 端口防火墙入站规则。", nil
}

func main() {
	showVersion := flag.Bool("v", false, "显示 GUI 版本号并退出")
	flag.BoolVar(showVersion, "version", false, "显示 GUI 版本号并退出")
	flag.Parse()

	if *showVersion {
		fmt.Printf("diting-gui version %s (built: %s, commit: %s)\n", Version, BuildTime, GitCommit)
		return
	}

	app := NewApp()

	err := wails.Run(&options.App{
		Title:     "谛听 (DITING) DNS 控制台",
		Width:     1280,
		Height:    720,
		MinWidth:  1280,
		MinHeight: 720,
		AssetServer: &assetserver.Options{
			Assets: frontend.Assets,
		},
		BackgroundColour: &options.RGBA{R: 27, G: 38, B: 54, A: 1},
		OnStartup:        app.startup,
		OnDomReady: func(ctx context.Context) {
			go func() {
				windows.LockWindowAspectRatio(windows.DefaultWindowTitle, 16.0/9.0)
			}()
		},
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		fmt.Fprintf(os.Stderr, "运行 GUI 失败: %v\n", err)
		os.Exit(1)
	}
}
