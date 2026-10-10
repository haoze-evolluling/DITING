package main

import (
	"context"
	"fmt"

	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// CheckPortConflicts 实现 ServiceController 接口
func (p *program) CheckPortConflicts(ctx context.Context) (*windows.PortCheckResult, error) {
	p.mu.Lock()
	if p.portChecker == nil {
		p.mu.Unlock()
		return nil, fmt.Errorf("端口检测器未初始化")
	}
	var udpAddrs, tcpAddrs []string
	if p.cfg != nil {
		udpAddrs, tcpAddrs = p.cfg.DNS.EffectiveListenAddresses()
	}
	portChecker := p.portChecker
	p.mu.Unlock()

	return portChecker.CheckPort53ForAddresses(ctx, udpAddrs, tcpAddrs)
}

// AutofixPortConflicts 实现 ServiceController 接口，自动停止/禁用 ICS 并可选拉起 DNS
func (p *program) AutofixPortConflicts(ctx context.Context, startDNS bool) (*windows.PortCheckResult, error) {
	p.mu.Lock()
	if p.portChecker == nil {
		p.mu.Unlock()
		return nil, fmt.Errorf("端口检测器未初始化")
	}
	var udpAddrs, tcpAddrs []string
	if p.cfg != nil {
		udpAddrs, tcpAddrs = p.cfg.DNS.EffectiveListenAddresses()
	}
	portChecker := p.portChecker
	p.mu.Unlock()

	res, err := portChecker.AutofixPort53ForAddresses(ctx, udpAddrs, tcpAddrs)
	if err != nil {
		return res, fmt.Errorf("自动修复端口冲突失败: %w", err)
	}
	if startDNS && res != nil && res.Available {
		p.mu.Lock()
		running := p.dnsRunning
		p.mu.Unlock()
		if !running {
			if err := p.StartDNS(ctx); err != nil {
				return res, fmt.Errorf("冲突已修复，但启动 DNS 失败: %w", err)
			}
		}
	}
	return res, nil
}

func fallbackPortConflict(err error) *windows.PortConflictError {
	return &windows.PortConflictError{
		Result: &windows.PortCheckResult{
			Available:  false,
			Diagnostic: "本地 53 端口已被占用，无法启动 DNS 监听器。排查建议：请检查是否有其他 DNS 或代理软件占用该端口。",
		},
		Err: err,
	}
}
