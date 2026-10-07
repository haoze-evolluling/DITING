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
	Version   = "0.1.0-dev"
	BuildTime = "dev"
	GitCommit = "dev"
)

// App 结构体
type App struct {
	ctx context.Context
}

// NewApp 构造函数
func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// Greet 测试方法
func (a *App) Greet(name string) string {
	return fmt.Sprintf("Hello %s, 来自谛听 (DITING) Windows GUI!", name)
}

// GetSystemAccentColor 获取 Windows 注册表中的强调色
func (a *App) GetSystemAccentColor() string {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\DWM`, registry.QUERY_VALUE)
	if err == nil {
		defer k.Close()
		val, _, err := k.GetIntegerValue("ColorizationColor")
		if err == nil {
			r := (val >> 16) & 0xFF
			g := (val >> 8) & 0xFF
			b := val & 0xFF
			return fmt.Sprintf("#%02x%02x%02x", r, g, b)
		}
	}
	return "#00668b"
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
		return "已成功自愈恢复系统 DNS 设置！", nil
	}
	return "系统 DNS 状态正常，未检测到残留接管。", nil
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
		Title:  "谛听 (DITING) DNS 控制台",
		Width:  1024,
		Height: 768,
		AssetServer: &assetserver.Options{
			Assets: frontend.Assets,
		},
		BackgroundColour: &options.RGBA{R: 27, G: 38, B: 54, A: 1},
		OnStartup:        app.startup,
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		fmt.Fprintf(os.Stderr, "运行 GUI 失败: %v\n", err)
		os.Exit(1)
	}
}
