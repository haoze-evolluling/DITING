package main

import (
	"context"
	"fmt"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// ConfigureAccess 实现 ServiceController 接口
func (p *program) ConfigureAccess(ctx context.Context, req ipc.ConfigureAccessRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := core.AccessControlConfig{
		AllowedClients: req.AllowedClients,
		BlockedClients: req.BlockedClients,
	}

	if p.accessControl != nil {
		if err := p.accessControl.Update(cfg); err != nil {
			return fmt.Errorf("更新客户端访问控制失败: %w", err)
		}
	}

	p.cfg.Access = cfg
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Access 配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureRateLimit 实现 ServiceController 接口
func (p *program) ConfigureRateLimit(ctx context.Context, req ipc.ConfigureRateLimitRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := core.RateLimitConfig{
		Enabled:    req.Enabled,
		Rate:       req.Rate,
		Burst:      req.Burst,
		IPv4Prefix: req.IPv4Prefix,
		IPv6Prefix: req.IPv6Prefix,
		ExemptIPs:  req.ExemptIPs,
	}

	if p.rateLimiter != nil {
		if err := p.rateLimiter.UpdateConfig(cfg); err != nil {
			return fmt.Errorf("更新限流配置失败: %w", err)
		}
	}

	p.cfg.RateLimit = cfg
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 RateLimit 配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureDNS64 实现 ServiceController 接口
func (p *program) ConfigureDNS64(ctx context.Context, req ipc.ConfigureDNS64Request) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := core.DNS64Config{
		Enabled:  req.Enabled,
		Prefixes: req.Prefixes,
	}

	if p.dns64Synth != nil {
		if err := p.dns64Synth.UpdateConfig(cfg); err != nil {
			return fmt.Errorf("更新 DNS64 配置失败: %w", err)
		}
	}

	p.cfg.DNS64 = cfg
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 DNS64 配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureBlockUnqualified 实现 ServiceController 接口
func (p *program) ConfigureBlockUnqualified(ctx context.Context, req ipc.ConfigureBlockUnqualifiedRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	p.cfg.DNS.BlockUnqualified = req.BlockUnqualified
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 BlockUnqualified 配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigurePrivacy 实现 ServiceController 接口
func (p *program) ConfigurePrivacy(ctx context.Context, req ipc.ConfigurePrivacyRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if req.EnableEDE != nil {
		p.cfg.DNS.EnableEDE = *req.EnableEDE
	}
	if req.BlockPrivatePTR != nil {
		p.cfg.DNS.BlockPrivatePTR = *req.BlockPrivatePTR
	}
	if req.BlockIPv6 != nil {
		p.cfg.DNS.BlockIPv6 = *req.BlockIPv6
	}
	if req.BlockECH != nil {
		p.cfg.DNS.BlockECH = *req.BlockECH
	}
	if req.EDNSPadding != nil {
		padding := *req.EDNSPadding
		if padding < 0 {
			padding = 0
		}
		// 先同步引擎再改共享配置：引擎拒绝（如上游列表为空）时必须整体失败，
		// 否则内存配置与磁盘落盘已是新值、运行中的 resolver 仍是旧值，
		// 当前会话行为与重启后不一致，而界面显示「已更新」。
		if p.resolver != nil {
			next := p.cfg.Upstream
			next.EDNSPadding = padding
			if err := p.resolver.Configure(next); err != nil {
				return fmt.Errorf("更新 EDNS 填充配置失败: %w", err)
			}
		}
		p.cfg.DNS.EDNSPadding = padding
		p.cfg.Upstream.EDNSPadding = padding
	}
	if req.BlockANY != nil {
		p.cfg.DNS.BlockANY = *req.BlockANY
	}
	if req.BlockANYMode != nil {
		// 未知模式回落到 notimp，与配置载入时的归一化保持一致
		switch *req.BlockANYMode {
		case config.ANYModeRFC8482:
			p.cfg.DNS.BlockANYMode = config.ANYModeRFC8482
		default:
			p.cfg.DNS.BlockANYMode = config.ANYModeNotImp
		}
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Privacy 配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureRebind 实现 ServiceController 接口
func (p *program) ConfigureRebind(ctx context.Context, req ipc.ConfigureRebindRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if req.Enabled != nil {
		p.cfg.Rebind.Enabled = *req.Enabled
	}
	if req.AllowedDomains != nil {
		p.cfg.Rebind.AllowedDomains = req.AllowedDomains
	}

	if p.rebindMgr != nil {
		p.rebindMgr.UpdateConfig(p.cfg.Rebind)
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Rebind 配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureHosts 实现 ServiceController 接口
func (p *program) ConfigureHosts(ctx context.Context, req ipc.ConfigureHostsRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if req.Enabled != nil {
		p.cfg.Hosts.Enabled = *req.Enabled
	}
	if req.UseSystemHost != nil {
		p.cfg.Hosts.UseSystemHost = *req.UseSystemHost
	}
	if req.CustomFiles != nil {
		p.cfg.Hosts.CustomFiles = req.CustomFiles
	}
	// 显式提交非正 TTL 视为非法输入而非「未提供」：静默丢弃后仍报成功，
	// 用户会以为已保存。0 在这里没有「不缓存」的合法语义，故直接拒绝。
	if req.TTL != nil {
		if *req.TTL <= 0 {
			return fmt.Errorf("TTL 必须为正整数")
		}
		p.cfg.Hosts.TTL = *req.TTL
	}

	if p.hostsResolver != nil {
		_ = p.hostsResolver.UpdateConfig(p.cfg.Hosts)
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Hosts 配置失败: %v\n", err)
		}
	}
	return nil
}


