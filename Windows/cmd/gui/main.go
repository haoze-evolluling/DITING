package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/haoze-evolluling/diting/windows/frontend"
	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
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
