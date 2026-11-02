package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

var validBgExts = []string{".webp", ".png", ".jpg", ".jpeg", ".svg"}

func (p *program) getBackgroundStorageDir() string {
	cfgPath := p.configPath
	if cfgPath == "" {
		cfgPath = config.GetDefaultConfigPath()
	}
	return filepath.Dir(cfgPath)
}

func (p *program) findExistingBgFile() (string, error) {
	dir := p.getBackgroundStorageDir()
	for _, ext := range validBgExts {
		path := filepath.Join(dir, "login_bg"+ext)
		if fi, err := os.Stat(path); err == nil && !fi.IsDir() && fi.Size() > 0 {
			return path, nil
		}
	}
	return "", os.ErrNotExist
}

func (p *program) cleanExistingBgFiles() {
	dir := p.getBackgroundStorageDir()
	for _, ext := range append(validBgExts, ".tmp") {
		matches, _ := filepath.Glob(filepath.Join(dir, "login_bg*"+ext))
		for _, f := range matches {
			_ = os.Remove(f)
		}
	}
}

// detectImageType 依据文件头真实魔数嗅探图片类型与 MIME
func detectImageType(data []byte) (ext string, contentType string, ok bool) {
	if len(data) < 3 {
		return "", "", false
	}
	// PNG
	if len(data) >= 8 && bytes.Equal(data[:8], []byte("\x89PNG\r\n\x1a\n")) {
		return ".png", "image/png", true
	}
	// JPEG
	if len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
		return ".jpg", "image/jpeg", true
	}
	// WebP
	if len(data) >= 12 && string(data[0:4]) == "RIFF" && string(data[8:12]) == "WEBP" {
		return ".webp", "image/webp", true
	}
	// SVG
	checkLen := min(len(data), 4096)
	header := strings.ToLower(string(data[:checkLen]))
	if strings.Contains(header, "<svg") || (strings.Contains(header, "<?xml") && strings.Contains(header, "svg")) {
		return ".svg", "image/svg+xml", true
	}
	return "", "", false
}

// GetLoginBackground 实现 ServiceController 接口
func (p *program) GetLoginBackground(ctx context.Context) (*ipc.LoginBackgroundResponse, error) {
	p.mu.Lock()
	bg := p.cfg.Web.Background
	p.mu.Unlock()

	// 容灾检查：若配置为 custom 本地图片，检查磁盘文件是否存在
	if bg.Type == "custom" {
		filePath, err := p.findExistingBgFile()
		if err != nil || filePath == "" {
			return &ipc.LoginBackgroundResponse{
				Type:      "none",
				URL:       "",
				Opacity:   40,
				Blur:      0,
				UpdatedAt: bg.UpdatedAt,
			}, nil
		}
		bgURL := fmt.Sprintf("/api/v1/auth/background/image?t=%d", bg.UpdatedAt)
		return &ipc.LoginBackgroundResponse{
			Type:      "custom",
			URL:       bgURL,
			Opacity:   bg.Opacity,
			Blur:      bg.Blur,
			UpdatedAt: bg.UpdatedAt,
		}, nil
	}

	if bg.Type == "url" && bg.URL != "" {
		return &ipc.LoginBackgroundResponse{
			Type:      "url",
			URL:       bg.URL,
			Opacity:   bg.Opacity,
			Blur:      bg.Blur,
			UpdatedAt: bg.UpdatedAt,
		}, nil
	}

	return &ipc.LoginBackgroundResponse{
		Type:      "none",
		URL:       "",
		Opacity:   40,
		Blur:      0,
		UpdatedAt: bg.UpdatedAt,
	}, nil
}

// SetLoginBackground 实现 ServiceController 接口
func (p *program) SetLoginBackground(ctx context.Context, req ipc.SetLoginBackgroundRequest) error {
	opacity := req.Opacity
	if opacity < 0 {
		opacity = 0
	} else if opacity > 100 {
		opacity = 100
	}

	blur := req.Blur
	if blur < 0 {
		blur = 0
	} else if blur > 20 {
		blur = 20
	}

	trimmedURL := strings.TrimSpace(req.URL)

	// 1. 本地图片 Base64 上传处理
	if strings.HasPrefix(trimmedURL, "data:image/") {
		commaIdx := strings.Index(trimmedURL, ",")
		if commaIdx == -1 {
			return fmt.Errorf("无效的图片 Data URL 数据格式")
		}
		rawB64 := trimmedURL[commaIdx+1:]

		// 清洗空格与换行符
		cleanB64 := strings.Map(func(r rune) rune {
			if r == ' ' || r == '\n' || r == '\r' || r == '\t' {
				return -1
			}
			return r
		}, rawB64)

		imgBytes, err := base64.StdEncoding.DecodeString(cleanB64)
		if err != nil {
			imgBytes, err = base64.URLEncoding.DecodeString(cleanB64)
			if err != nil {
				return fmt.Errorf("图片 Base64 解码失败: %w", err)
			}
		}

		if len(imgBytes) == 0 {
			return fmt.Errorf("图片数据内容为空")
		}
		if len(imgBytes) > 10*1024*1024 {
			return fmt.Errorf("图片数据体积过大 (超过 10MB 限额)")
		}

		// 格式有效性验证与后缀识别
		ext, _, ok := detectImageType(imgBytes)
		if !ok {
			return fmt.Errorf("图片文件头校验失败，仅支持 WebP、PNG、JPEG 与 SVG 格式")
		}

		dir := p.getBackgroundStorageDir()
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("创建背景存储目录失败: %w", err)
		}

		tmpFile, err := os.CreateTemp(dir, "bg_upload_*.tmp")
		if err != nil {
			return fmt.Errorf("创建背景临时文件失败: %w", err)
		}
		tmpPath := tmpFile.Name()
		defer func() {
			_ = os.Remove(tmpPath)
		}()

		if _, err := tmpFile.Write(imgBytes); err != nil {
			_ = tmpFile.Close()
			return fmt.Errorf("写入背景临时文件失败: %w", err)
		}
		if err := tmpFile.Sync(); err != nil {
			_ = tmpFile.Close()
			return fmt.Errorf("同步背景临时文件失败: %w", err)
		}
		_ = tmpFile.Close()

		targetPath := filepath.Join(dir, "login_bg"+ext)
		p.cleanExistingBgFiles()
		_ = os.Remove(targetPath)
		if err := os.Rename(tmpPath, targetPath); err != nil {
			return fmt.Errorf("持久化背景图片文件失败: %w", err)
		}

		p.mu.Lock()
		p.cfg.Web.Background = config.LoginBgConfig{
			Type:      "custom",
			URL:       "/api/v1/auth/background/image",
			Opacity:   opacity,
			Blur:      blur,
			UpdatedAt: time.Now().Unix(),
		}
		saveErr := config.SaveConfig(p.configPath, p.cfg)
		p.mu.Unlock()
		if saveErr != nil {
			return fmt.Errorf("保存服务配置文件失败: %w", saveErr)
		}
		return nil
	}

	// 2. 更新已有自定义背景视觉参数 (无需重新上传图片)
	if req.Type == "custom" || strings.Contains(trimmedURL, "/api/v1/auth/background/image") {
		filePath, err := p.findExistingBgFile()
		if err != nil || filePath == "" {
			return fmt.Errorf("服务端尚未存储自定义背景图片，请先上传本地图片")
		}

		p.mu.Lock()
		p.cfg.Web.Background = config.LoginBgConfig{
			Type:      "custom",
			URL:       "/api/v1/auth/background/image",
			Opacity:   opacity,
			Blur:      blur,
			UpdatedAt: time.Now().Unix(),
		}
		saveErr := config.SaveConfig(p.configPath, p.cfg)
		p.mu.Unlock()
		if saveErr != nil {
			return fmt.Errorf("保存服务配置文件失败: %w", saveErr)
		}
		return nil
	}

	// 3. 外部网络 URL 处理
	if strings.HasPrefix(trimmedURL, "http://") || strings.HasPrefix(trimmedURL, "https://") {
		if len(trimmedURL) > 2048 {
			return fmt.Errorf("图片网络链接长度超过 2048 字符上限")
		}

		p.cleanExistingBgFiles()
		p.mu.Lock()
		p.cfg.Web.Background = config.LoginBgConfig{
			Type:      "url",
			URL:       trimmedURL,
			Opacity:   opacity,
			Blur:      blur,
			UpdatedAt: time.Now().Unix(),
		}
		saveErr := config.SaveConfig(p.configPath, p.cfg)
		p.mu.Unlock()
		if saveErr != nil {
			return fmt.Errorf("保存服务配置文件失败: %w", saveErr)
		}
		return nil
	}

	// 4. 空 URL 或 type == "none"，等同于重置为默认背景
	return p.ResetLoginBackground(ctx)
}

// ResetLoginBackground 实现 ServiceController 接口
func (p *program) ResetLoginBackground(ctx context.Context) error {
	p.cleanExistingBgFiles()
	p.mu.Lock()
	p.cfg.Web.Background = config.LoginBgConfig{
		Type:      "none",
		URL:       "",
		Opacity:   40,
		Blur:      0,
		UpdatedAt: time.Now().Unix(),
	}
	saveErr := config.SaveConfig(p.configPath, p.cfg)
	p.mu.Unlock()
	if saveErr != nil {
		return fmt.Errorf("保存服务配置文件失败: %w", saveErr)
	}
	return nil
}

// GetLoginBackgroundImage 实现 ServiceController 接口
func (p *program) GetLoginBackgroundImage(ctx context.Context) ([]byte, string, time.Time, error) {
	filePath, err := p.findExistingBgFile()
	if err != nil {
		return nil, "", time.Time{}, os.ErrNotExist
	}

	info, err := os.Stat(filePath)
	if err != nil {
		return nil, "", time.Time{}, err
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, "", time.Time{}, err
	}

	ext := strings.ToLower(filepath.Ext(filePath))
	contentType := "image/webp"
	switch ext {
	case ".png":
		contentType = "image/png"
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".svg":
		contentType = "image/svg+xml"
	case ".webp":
		contentType = "image/webp"
	}

	return data, contentType, info.ModTime(), nil
}

// VerifyAdminPassword 实现 ServiceController 接口
func (p *program) VerifyAdminPassword(ctx context.Context, plainPassword string) bool {
	if p.authMgr == nil {
		return false
	}
	return p.authMgr.VerifyPassword(plainPassword)
}

// VerifyAdminPasswordWithIP 实现 ServiceController 接口
func (p *program) VerifyAdminPasswordWithIP(ctx context.Context, clientIP, plainPassword string) (bool, error) {
	if p.authMgr == nil {
		return false, fmt.Errorf("认证管理器未初始化")
	}
	return p.authMgr.VerifyPasswordWithIP(clientIP, plainPassword)
}

// IsAuthInitialized 实现 ServiceController 接口
func (p *program) IsAuthInitialized() bool {
	if p.authMgr == nil {
		return false
	}
	return p.authMgr.IsInitialized()
}
