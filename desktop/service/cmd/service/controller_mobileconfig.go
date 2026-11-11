package main

import (
	"context"
	"fmt"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// BuildEncryptedMobileConfig 生成 Apple 配置描述文件（.mobileconfig）。
//
// protocol 为空时按当前启用的监听器挑选，优先 DoH：iOS 对 HTTPS 型
// 描述文件的支持最完整，TLS 型还需要设备额外信任服务端证书。
func (p *program) BuildEncryptedMobileConfig(ctx context.Context, protocol string) ([]byte, error) {
	status, err := p.GetEncryptedDNS(ctx)
	if err != nil {
		return nil, err
	}
	cfg := status.Config
	if !cfg.Enabled {
		return nil, fmt.Errorf("加密 DNS 服务未启用")
	}
	if strings.TrimSpace(cfg.ServerName) == "" {
		return nil, fmt.Errorf("尚未配置服务器名，无法生成描述文件")
	}

	chosen := strings.ToUpper(strings.TrimSpace(protocol))
	if chosen == "" {
		switch {
		case cfg.DoHEnabled && strings.TrimSpace(status.DoHListen) != "":
			chosen = core.MobileConfigProtocolHTTPS
		case cfg.DoTEnabled && strings.TrimSpace(status.DoTListen) != "":
			chosen = core.MobileConfigProtocolTLS
		default:
			return nil, fmt.Errorf("没有正在运行的加密监听器：请先启用 DoH 或 DoT 并确认端口已绑定")
		}
	}

	opts := core.MobileConfigOptions{
		ServerName:  cfg.ServerName,
		Protocol:    chosen,
		DisplayName: "DITING 加密 DNS",
		UUID:        cfg.UUID,
	}
	if chosen == core.MobileConfigProtocolHTTPS {
		// 取界面展示的候选列表首项（服务器名优先），保证与 DDR 广播、
		// 用户手工填写三者看到的是同一个地址
		if len(status.DoHURLs) == 0 {
			return nil, fmt.Errorf("无法构造 DoH 地址：请检查服务器名与端口配置")
		}
		opts.ServerURL = status.DoHURLs[0]
	}

	uuid, err := p.ensureEncryptedUUID()
	if err != nil {
		return nil, err
	}
	opts.UUID = uuid

	return core.BuildMobileConfig(opts)
}

// ensureEncryptedUUID 返回配置里固定的描述文件 UUID，没有就生成并落盘。
//
// 必须持久化：每次下载都换一个 UUID 会让设备里堆满外观相同、
// 实际互相冲突的描述文件，而同一个 UUID 的新文件会被当作更新。
func (p *program) ensureEncryptedUUID() (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if cfg := p.cfg.Encrypted; strings.TrimSpace(cfg.UUID) != "" {
		return cfg.UUID, nil
	}

	id, err := core.EnsureEncryptedUUID(&p.cfg.Encrypted)
	if err != nil {
		return "", err
	}
	p.persistConfigLocked("加密 DNS 描述文件标识")
	return id, nil
}
