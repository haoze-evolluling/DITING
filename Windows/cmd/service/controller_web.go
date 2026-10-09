package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"strconv"

	"github.com/haoze-evolluling/diting/windows/internal/config"
	"github.com/haoze-evolluling/diting/windows/internal/ipc"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

func (p *program) effectiveWebPort() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.cfg.Web.ListenPort > 0 {
		return p.cfg.Web.ListenPort
	}
	// 从 IPC 监听地址中解析端口
	_, portStr, err := net.SplitHostPort(p.cfg.IPC.ListenAddress)
	if err == nil {
		if pt, err := strconv.Atoi(portStr); err == nil && pt > 0 {
			return pt
		}
	}
	return 15353
}

// GetWebStatus 实现 ServiceController 接口
func (p *program) GetWebStatus(ctx context.Context) (*ipc.WebStatusResponse, error) {
	p.mu.Lock()
	webEnabled := p.cfg.Web.Enabled
	listenAddr := p.cfg.IPC.ListenAddress
	p.mu.Unlock()

	effPort := p.effectiveWebPort()

	lanAddrs, err := windows.GetLANAddresses()
	if err != nil {
		log.Printf("[Web] 获取本机局域网地址警告: %v\n", err)
	}

	var webURLs []string
	for _, ip := range lanAddrs {
		webURLs = append(webURLs, fmt.Sprintf("http://%s:%d", ip, effPort))
	}
	if len(webURLs) == 0 {
		webURLs = append(webURLs, fmt.Sprintf("http://127.0.0.1:%d", effPort))
	}

	fwAllowed, _ := windows.CheckFirewallPortWeb(ctx, windows.NewDefaultExecutor())

	initialized := false
	username := "admin"
	if p.authMgr != nil {
		initialized = p.authMgr.IsInitialized()
		username = p.authMgr.GetUsername()
	}

	return &ipc.WebStatusResponse{
		Enabled:         webEnabled,
		Port:            effPort,
		ListenAddress:   listenAddr,
		LANAddresses:    lanAddrs,
		WebURLs:         webURLs,
		FirewallAllowed: fwAllowed,
		Initialized:     initialized,
		Username:        username,
	}, nil
}

// ConfigureWeb 实现 ServiceController 接口
func (p *program) ConfigureWeb(ctx context.Context, req ipc.ConfigureWebRequest) error {
	p.mu.Lock()
	wasEnabled := p.cfg.Web.Enabled
	p.cfg.Web.Enabled = req.Enabled
	if req.Port > 0 {
		p.cfg.Web.ListenPort = req.Port
	}
	port := p.cfg.Web.ListenPort
	if port <= 0 {
		port = 15353
	}

	// 动态调整 IPC 监听地址 (启用局域网 Web 时监听 0.0.0.0)
	if req.Enabled {
		p.cfg.IPC.ListenAddress = fmt.Sprintf("0.0.0.0:%d", port)
	} else {
		p.cfg.IPC.ListenAddress = fmt.Sprintf("127.0.0.1:%d", port)
	}

	// 持久化保存配置
	if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
		log.Printf("[配置] 保存 Web 配置失败: %v\n", err)
	}
	p.mu.Unlock()

	// 按需同步配置 Windows 防火墙规则
	if req.ConfigureFirewall {
		executor := windows.NewDefaultExecutor()
		if err := windows.ConfigureFirewallPortWeb(ctx, executor, port, req.Enabled); err != nil {
			log.Printf("[防火墙] 配置 Web 端口规则警告: %v\n", err)
		} else {
			log.Printf("[防火墙] 已成功同步 Web 端口入站规则 (端口: %d, 启用: %v)\n", port, req.Enabled)
		}
	}

	// 若运行状态或监听发生变化，平滑重启 IPC/Web 服务
	if wasEnabled != req.Enabled && p.ipcServer != nil {
		log.Printf("[Web] 正在平滑重启服务以应用新监听设置 (%s)...\n", p.cfg.IPC.ListenAddress)
		_ = p.ipcServer.Shutdown(ctx)
		newServer := ipc.NewServer(p.cfg.IPC.ListenAddress, p.cfg.IPC.AuthToken, p)
		p.initAssetsForServer(newServer)
		if err := newServer.Start(); err != nil {
			log.Printf("[Web] 重启服务失败: %v\n", err)
		} else {
			p.ipcServer = newServer
			log.Printf("[Web] 服务已成功平滑重启于: %s\n", newServer.Addr())
		}
	}

	return nil
}

// ConfigureWebFirewall 实现 ServiceController 接口
func (p *program) ConfigureWebFirewall(ctx context.Context, enable bool) error {
	return windows.ConfigureFirewallPortWeb(ctx, windows.NewDefaultExecutor(), p.effectiveWebPort(), enable)
}

// GetAuthStatus 实现 ServiceController 接口
func (p *program) GetAuthStatus(ctx context.Context) (*ipc.AuthStatusResponse, error) {
	p.mu.Lock()
	webEnabled := p.cfg.Web.Enabled
	p.mu.Unlock()

	if p.authMgr == nil {
		return &ipc.AuthStatusResponse{
			Initialized:   false,
			WebEnabled:    webEnabled,
			Authenticated: false,
			Username:      "admin",
		}, nil
	}

	return &ipc.AuthStatusResponse{
		Initialized:   p.authMgr.IsInitialized(),
		WebEnabled:    webEnabled,
		Authenticated: false,
		Username:      p.authMgr.GetUsername(),
	}, nil
}

// Login 实现 ServiceController 接口
func (p *program) Login(ctx context.Context, req ipc.LoginRequest, clientIP string) (*ipc.LoginResponse, error) {
	if p.authMgr == nil {
		return nil, fmt.Errorf("认证管理器未就绪")
	}
	sess, err := p.authMgr.Login(req.Username, req.Password, clientIP)
	if err != nil {
		return nil, err
	}
	return &ipc.LoginResponse{
		Token:     sess.Token,
		Username:  sess.Username,
		ExpiresAt: sess.ExpiresAt.Unix(),
	}, nil
}

// Logout 实现 ServiceController 接口
func (p *program) Logout(ctx context.Context, token string) error {
	if p.authMgr != nil {
		p.authMgr.RevokeSession(token)
	}
	return nil
}

// SetupAuth 实现 ServiceController 接口
func (p *program) SetupAuth(ctx context.Context, req ipc.SetupAuthRequest) error {
	if p.authMgr == nil {
		return fmt.Errorf("认证管理器未就绪")
	}
	if err := p.authMgr.SetupInitialCredentials(req.Username, req.Password); err != nil {
		return err
	}

	// 同步回存至持久化配置
	p.mu.Lock()
	username, passHash, salt := p.authMgr.GetCredentials()
	p.cfg.Web.Username = username
	p.cfg.Web.PasswordHash = passHash
	p.cfg.Web.Salt = salt
	_ = config.SaveConfig(p.configPath, p.cfg)
	p.mu.Unlock()

	return nil
}

// ChangePassword 实现 ServiceController 接口
func (p *program) ChangePassword(ctx context.Context, req ipc.ChangePasswordRequest, bypassOldAuth bool) error {
	if p.authMgr == nil {
		return fmt.Errorf("认证管理器未就绪")
	}
	if err := p.authMgr.UpdateCredentials(req.Username, req.OldPassword, req.NewPassword, bypassOldAuth); err != nil {
		return err
	}

	// 同步回存至持久化配置
	p.mu.Lock()
	username, passHash, salt := p.authMgr.GetCredentials()
	p.cfg.Web.Username = username
	p.cfg.Web.PasswordHash = passHash
	p.cfg.Web.Salt = salt
	_ = config.SaveConfig(p.configPath, p.cfg)
	p.mu.Unlock()

	return nil
}

// ValidateSession 实现 ServiceController 接口
func (p *program) ValidateSession(token string) bool {
	if p.authMgr == nil {
		return false
	}
	_, ok := p.authMgr.ValidateSession(token)
	return ok
}
