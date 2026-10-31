//go:build windows

package main

import (
	"context"
	"fmt"
	"os"

	flutterfrontend "github.com/haoze-evolluling/diting/desktop/flutter_frontend"
	"github.com/haoze-evolluling/diting/desktop/internal/platform"
	"github.com/haoze-evolluling/diting/desktop/internal/platform/windows"
	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

// NewApp 为 Windows 平台构造带有完整原生实现的 App 实例。
func NewApp() *App {
	exec := platform.NewDefaultExecutor()
	// 与服务端同源解析状态文件路径：服务可能配置了自定义 takeover.stateFilePath，
	// GUI 的应急恢复必须读同一份文件，否则会误报「无残留接管」。
	store := platform.NewFileStateStore(platform.ResolveStateFilePath("", ""))
	dnsMgr := windows.NewDNSManager(exec, store, Version)
	serviceMgr := windows.NewServiceManager(exec, nil)
	autoStart := windows.NewAutoStartManager()
	capturer := windows.NewWindowCapturer()
	aspectRatio := windows.NewAspectRatioManager()
	firewall := windows.NewFirewallManager(exec)
	trayMgr := windows.NewTrayManager()

	return &App{
		serviceMgr:  serviceMgr,
		autoStart:   autoStart,
		capturer:    capturer,
		aspectRatio: aspectRatio,
		firewall:    firewall,
		dnsMgr:      dnsMgr,
		stateStore:  store,
		tray:        trayMgr,
		version:     Version,
	}
}

// runGUI 启动 Windows 平台 Wails GUI 窗口应用。
func runGUI(app *App, startMinimized bool) {
	err := wails.Run(&options.App{
		Title:             "谛听 (DITING) DNS 控制台",
		Width:             1280,
		Height:            720,
		MinWidth:          720,
		MinHeight:         560,
		StartHidden:       startMinimized,
		HideWindowOnClose: true,
		SingleInstanceLock: &options.SingleInstanceLock{
			UniqueId: "diting-dns-gui-single-instance-lock",
			OnSecondInstanceLaunch: func(secondInstanceData options.SecondInstanceData) {
				if app != nil {
					app.ShowWindow()
				}
			},
		},
		AssetServer: &assetserver.Options{
			Assets: flutterfrontend.Assets,
		},
		BackgroundColour: &options.RGBA{R: 17, G: 20, B: 24, A: 1},
		OnStartup: func(ctx context.Context) {
			app.startup(ctx)
		},
		OnDomReady: func(ctx context.Context) {
			// Flutter UI 支持任意窗口比例，不再强制锁定 16:9。
			app.initTray()
		},
		OnShutdown: func(ctx context.Context) {
			if app.tray != nil {
				app.tray.Destroy()
			}
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
