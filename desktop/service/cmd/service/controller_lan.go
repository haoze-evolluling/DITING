package main

import (
	"context"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// GetLANStatus 实现 ServiceController 接口
func (p *program) GetLANStatus(ctx context.Context) (*ipc.LANStatusResponse, error) {
	p.mu.Lock()
	allowLAN := p.cfg.DNS.AllowLAN
	udpAddrs, _ := p.cfg.DNS.EffectiveListenAddresses()
	p.mu.Unlock()

	lanAddrs, err := platform.GetLANAddresses()
	if err != nil {
		log.Printf("[LAN] 获取本机局域网地址警告: %v\n", err)
	}

	fwAllowed, _ := firewallCheckPort53(ctx)

	return &ipc.LANStatusResponse{
		AllowLAN:        allowLAN,
		ListenAddresses: udpAddrs,
		LANAddresses:    lanAddrs,
		FirewallAllowed: fwAllowed,
		FirewallBackend: firewallBackendName(),
	}, nil
}

// ConfigureLAN 实现 ServiceController 接口
func (p *program) ConfigureLAN(ctx context.Context, req ipc.ConfigureLANRequest) error {
	p.mu.Lock()
	wasRunning := p.dnsRunning
	p.cfg.DNS.AllowLAN = req.AllowLAN
	newUDP, newTCP := p.cfg.DNS.EffectiveListenAddresses()
	p.cfg.DNS.UDPAddresses = newUDP
	p.cfg.DNS.TCPAddresses = newTCP

	// 持久化保存配置
	if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
		log.Printf("[配置] 保存 AllowLAN 配置失败: %v\n", err)
	}
	p.mu.Unlock()

	// 按需自动配置系统防火墙规则；无防火墙后端时端口本就开放，跳过且不记为错误
	if req.ConfigureFirewall && firewallBackendName() != "none" {
		if err := firewallConfigurePort53(ctx, req.AllowLAN); err != nil {
			log.Printf("[防火墙] 自动配置 53 端口规则警告: %v\n", err)
		} else {
			log.Printf("[防火墙] 已成功同步 53 端口入站规则 (启用: %v)\n", req.AllowLAN)
		}
	}

	// 若当前 DNS 服务正在运行，无缝重启监听器使新绑定地址立即生效
	if wasRunning {
		log.Println("[LAN] 检测到 DNS 监听器运行中，正在平滑重载监听器以应用局域网模式...")
		wasTakeoverActive := p.takeoverMgr != nil && p.takeoverMgr.IsTakeoverActive()
		if err := p.StopDNS(ctx); err != nil {
			log.Printf("[LAN] 停止原有监听器警告: %v\n", err)
		}
		if err := p.StartDNS(ctx); err != nil {
			return err
		}
		if wasTakeoverActive {
			if err := p.EnableTakeover(ctx); err != nil {
				log.Printf("[LAN] 恢复系统 DNS 接管警告: %v\n", err)
			}
		}
	}

	return nil
}

// ConfigureFirewall 实现 ServiceController 接口
func (p *program) ConfigureFirewall(ctx context.Context, enable bool) error {
	return firewallConfigurePort53(ctx, enable)
}
