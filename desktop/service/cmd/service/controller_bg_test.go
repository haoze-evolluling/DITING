package main

import (
	"context"
	"encoding/base64"
	"path/filepath"
	"strings"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/auth"
	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

func TestController_BackgroundWorkflow(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.json")
	cfg := config.DefaultConfig()

	authMgr := auth.NewManager("admin", "", "", 0)
	_ = authMgr.SetupInitialCredentials("admin", "Admin1234")

	p := &program{
		configPath: cfgPath,
		cfg:        cfg,
		authMgr:    authMgr,
	}
	ctx := context.Background()

	// 1. 初始状态：应为默认极简渐变背景 (无自定义图片)
	initialBg, err := p.GetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackground failed: %v", err)
	}
	if initialBg.Type != "none" || initialBg.URL != "" || initialBg.Opacity != 40 || initialBg.Blur != 0 {
		t.Fatalf("expected default background, got %+v", initialBg)
	}

	// 2. 外部网络 URL 配置与全局持久化
	err = p.SetLoginBackground(ctx, ipc.SetLoginBackgroundRequest{
		Type:    "url",
		URL:     "https://cdn.example.com/wallpaper.png",
		Opacity: 60,
		Blur:    5,
	})
	if err != nil {
		t.Fatalf("SetLoginBackground with URL failed: %v", err)
	}

	urlBg, err := p.GetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackground failed: %v", err)
	}
	if urlBg.Type != "url" || urlBg.URL != "https://cdn.example.com/wallpaper.png" || urlBg.Opacity != 60 || urlBg.Blur != 5 {
		t.Fatalf("unexpected url background: %+v", urlBg)
	}

	// 检查持久化至 config.json 文件
	reloadedCfg, err := config.LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("LoadConfig failed: %v", err)
	}
	if reloadedCfg.Web.Background.URL != "https://cdn.example.com/wallpaper.png" {
		t.Fatalf("config file was not updated with url: %+v", reloadedCfg.Web.Background)
	}

	// 3. 上传 WebP 本地图片 Base64
	fakeWebp := append([]byte("RIFF1234WEBP"), []byte("...imagedata...")...)
	webpDataUrl := "data:image/webp;base64," + base64.StdEncoding.EncodeToString(fakeWebp)

	err = p.SetLoginBackground(ctx, ipc.SetLoginBackgroundRequest{
		URL:     webpDataUrl,
		Opacity: 70,
		Blur:    3,
	})
	if err != nil {
		t.Fatalf("SetLoginBackground with webp failed: %v", err)
	}

	customBg, err := p.GetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackground failed: %v", err)
	}
	if customBg.Type != "custom" || !strings.HasPrefix(customBg.URL, "/api/v1/auth/background/image") || customBg.Opacity != 70 {
		t.Fatalf("unexpected custom background: %+v", customBg)
	}

	// 检查磁盘上的图片文件
	bgFile, err := p.findExistingBgFile()
	if err != nil {
		t.Fatalf("background file not found on disk: %v", err)
	}
	if filepath.Ext(bgFile) != ".webp" {
		t.Fatalf("expected .webp extension, got %s", bgFile)
	}

	// 获取图片二进制流
	imgData, mime, _, err := p.GetLoginBackgroundImage(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackgroundImage failed: %v", err)
	}
	if mime != "image/webp" || string(imgData) != string(fakeWebp) {
		t.Fatalf("unexpected image content or mime: %s, %s", mime, string(imgData))
	}

	// 4. 上传 PNG 替换 WebP（验证旧文件清理与新格式写入）
	fakePng := append([]byte("\x89PNG\r\n\x1a\n"), []byte("...pngdata...")...)
	pngDataUrl := "data:image/png;base64," + base64.StdEncoding.EncodeToString(fakePng)

	err = p.SetLoginBackground(ctx, ipc.SetLoginBackgroundRequest{
		URL:     pngDataUrl,
		Opacity: 50,
		Blur:    0,
	})
	if err != nil {
		t.Fatalf("SetLoginBackground with png failed: %v", err)
	}

	// 检查旧的 .webp 文件已被清理，只保留 .png
	matches, _ := filepath.Glob(filepath.Join(tmpDir, "login_bg.*"))
	if len(matches) != 1 || filepath.Ext(matches[0]) != ".png" {
		t.Fatalf("expected exactly one .png file, got %v", matches)
	}

	// 4.1 核心防护测试：仅微调暗度与模糊度时，必须保留已有磁盘图片，不得误删或重置
	err = p.SetLoginBackground(ctx, ipc.SetLoginBackgroundRequest{
		Type:    "custom",
		URL:     "http://192.168.1.182:15353/api/v1/auth/background/image?t=123456",
		Opacity: 88,
		Blur:    12,
	})
	if err != nil {
		t.Fatalf("updating visual config on existing custom background failed: %v", err)
	}
	retainedBg, err := p.GetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackground failed: %v", err)
	}
	if retainedBg.Type != "custom" || retainedBg.Opacity != 88 || retainedBg.Blur != 12 {
		t.Fatalf("expected retained custom background with updated opacity/blur, got %+v", retainedBg)
	}
	// 验证磁盘上的 .png 图片依然存在且内容未变
	retainedImg, mime, _, err := p.GetLoginBackgroundImage(ctx)
	if err != nil {
		t.Fatalf("retained image missing from disk: %v", err)
	}
	if mime != "image/png" || string(retainedImg) != string(fakePng) {
		t.Fatalf("retained image corrupted: %s", mime)
	}

	// 4.2 SVG 矢量壁纸上传测试
	svgContent := []byte(`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle cx="50" cy="50" r="40"/></svg>`)
	svgDataUrl := "data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString(svgContent)
	err = p.SetLoginBackground(ctx, ipc.SetLoginBackgroundRequest{
		URL:     svgDataUrl,
		Opacity: 35,
		Blur:    2,
	})
	if err != nil {
		t.Fatalf("SetLoginBackground with svg failed: %v", err)
	}
	svgData, svgMime, _, err := p.GetLoginBackgroundImage(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackgroundImage for svg failed: %v", err)
	}
	if svgMime != "image/svg+xml" || string(svgData) != string(svgContent) {
		t.Fatalf("expected svg image/svg+xml, got %s", svgMime)
	}

	// 5. 模拟服务重启 (重启后从磁盘 config.json 读取并验证持久化)
	reloadedAfterUpload, err := config.LoadConfig(cfgPath)
	if err != nil {
		t.Fatalf("reloading config failed: %v", err)
	}
	restartedProg := &program{
		configPath: cfgPath,
		cfg:        reloadedAfterUpload,
		authMgr:    authMgr,
	}
	restartedBg, err := restartedProg.GetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("restarted GetLoginBackground failed: %v", err)
	}
	if restartedBg.Type != "custom" || !strings.HasPrefix(restartedBg.URL, "/api/v1/auth/background/image") {
		t.Fatalf("restarted background mismatch: %+v", restartedBg)
	}

	// 6. 一键恢复默认 (Reset)
	err = p.ResetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("ResetLoginBackground failed: %v", err)
	}

	resetBg, err := p.GetLoginBackground(ctx)
	if err != nil {
		t.Fatalf("GetLoginBackground after reset failed: %v", err)
	}
	if resetBg.Type != "none" || resetBg.URL != "" {
		t.Fatalf("expected reset background, got %+v", resetBg)
	}

	// 验证磁盘上的图片文件已被删除
	matchesAfterReset, _ := filepath.Glob(filepath.Join(tmpDir, "login_bg.*"))
	if len(matchesAfterReset) != 0 {
		t.Fatalf("expected 0 image files after reset, got %v", matchesAfterReset)
	}

	// 7. 管理员密码校验与 IP 频控防爆破测试
	if !p.VerifyAdminPassword(ctx, "Admin1234") {
		t.Fatalf("expected password verification to pass")
	}
	if p.VerifyAdminPassword(ctx, "WrongPassword") {
		t.Fatalf("expected wrong password to fail")
	}

	remoteIP := "192.168.1.99"
	ok, err := p.VerifyAdminPasswordWithIP(ctx, remoteIP, "Admin1234")
	if err != nil || !ok {
		t.Fatalf("expected VerifyAdminPasswordWithIP to pass: %v", err)
	}

	// 连续 5 次错误密码应触发锁定保护
	for i := 0; i < 5; i++ {
		ok, err = p.VerifyAdminPasswordWithIP(ctx, remoteIP, "bad-password")
		if ok {
			t.Fatalf("expected bad password to fail on attempt %d", i+1)
		}
	}
	// 第 6 次调用应处于锁定状态
	ok, err = p.VerifyAdminPasswordWithIP(ctx, remoteIP, "Admin1234")
	if ok || err == nil || !strings.Contains(err.Error(), "重试") {
		t.Fatalf("expected lockout protection to activate, got ok=%v, err=%v", ok, err)
	}
}

