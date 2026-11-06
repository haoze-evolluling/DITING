package main

import (
	"context"
	"fmt"
	"log"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// GetRewriteRules 获取当前所有 DNS 重写与伪装规则
func (p *program) GetRewriteRules(ctx context.Context) ([]core.RewriteRule, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.rewriteEngine != nil {
		return p.rewriteEngine.GetRules(), nil
	}
	return p.cfg.Rewrite.Rules, nil
}

// AddRewriteRule 动态添加或更新单条 DNS 重写规则
func (p *program) AddRewriteRule(ctx context.Context, rule core.RewriteRule) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.rewriteEngine != nil {
		if err := p.rewriteEngine.AddRule(rule); err != nil {
			return err
		}
		p.cfg.Rewrite.Rules = p.rewriteEngine.GetRules()
	} else {
		p.cfg.Rewrite.Rules = append(p.cfg.Rewrite.Rules, rule)
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Rewrite 规则失败: %v\n", err)
		}
	}
	return nil
}

// DeleteRewriteRule 删除指定域名的重写规则
func (p *program) DeleteRewriteRule(ctx context.Context, domain string) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.rewriteEngine != nil {
		found, err := p.rewriteEngine.DeleteRule(domain)
		if err != nil {
			return err
		}
		if !found {
			return fmt.Errorf("未找到对应域名的重写规则: %s", domain)
		}
		p.cfg.Rewrite.Rules = p.rewriteEngine.GetRules()
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Rewrite 规则失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureRewrite 整体更新 DNS 重写引擎配置
func (p *program) ConfigureRewrite(ctx context.Context, req ipc.ConfigureRewriteRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.Rewrite
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	// 显式提交非正 TTL 是非法输入而非「未提供」：静默丢弃仍报成功会让用户
	// 以为已保存，GET 回读却还是旧值。
	if req.TTL != nil {
		if *req.TTL <= 0 {
			return fmt.Errorf("TTL 必须为正整数")
		}
		cfg.TTL = *req.TTL
	}
	if req.Rules != nil {
		cfg.Rules = *req.Rules
	}

	if p.rewriteEngine != nil {
		if err := p.rewriteEngine.Configure(cfg); err != nil {
			return err
		}
	}

	p.cfg.Rewrite = cfg
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Rewrite 配置失败: %v\n", err)
		}
	}
	return nil
}

// GetClients 获取所有已识别的客户端信息
func (p *program) GetClients(ctx context.Context) ([]core.ClientInfo, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.clientResolver != nil {
		return p.clientResolver.GetClients(), nil
	}
	return []core.ClientInfo{}, nil
}

// ConfigureClientAlias 设置或更新客户端静态别名
func (p *program) ConfigureClientAlias(ctx context.Context, req ipc.ConfigureClientAliasRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if req.IP == "" {
		return fmt.Errorf("客户端 IP 不能为空")
	}

	if p.clientResolver != nil {
		p.clientResolver.SetAlias(req.IP, req.Name)
	}

	// 更新持久化别名列表
	found := false
	for i, a := range p.cfg.Client.Aliases {
		if a.IP == req.IP {
			if req.Name == "" {
				p.cfg.Client.Aliases = append(p.cfg.Client.Aliases[:i], p.cfg.Client.Aliases[i+1:]...)
			} else {
				p.cfg.Client.Aliases[i].Name = req.Name
			}
			found = true
			break
		}
	}
	if !found && req.Name != "" {
		p.cfg.Client.Aliases = append(p.cfg.Client.Aliases, core.ClientAlias{IP: req.IP, Name: req.Name})
	}

	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 Client 别名配置失败: %v\n", err)
		}
	}
	return nil
}

// ConfigureECS 更新 EDNS Client Subnet 处理策略
func (p *program) ConfigureECS(ctx context.Context, req ipc.ConfigureECSRequest) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	cfg := p.cfg.ECS
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	if req.StripECS != nil {
		cfg.StripECS = *req.StripECS
	}
	if req.CustomSubnet != nil {
		cfg.CustomSubnet = *req.CustomSubnet
	}

	if p.ecsMgr != nil {
		p.ecsMgr.Configure(cfg)
	}

	p.cfg.ECS = cfg
	if p.configPath != "" {
		if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
			log.Printf("[配置] 持久化 ECS 配置失败: %v\n", err)
		}
	}
	return nil
}
