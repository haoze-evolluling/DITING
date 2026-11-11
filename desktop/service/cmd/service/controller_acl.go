package main

import (
	"context"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
)

// ConfigureEncryptedACL 更新反向代理可信来源并持久化。
//
// 与端口、证书一样，可信列表只在监听器装配时读取一次，改完必须重建
// 监听器才生效——否则用户点了保存，实际生效的仍是旧列表。
func (p *program) ConfigureEncryptedACL(ctx context.Context, req ipc.ConfigureACLRequest) error {
	p.mu.Lock()
	defer func() {
		p.mu.Unlock()
		// 重建监听器必须发生在解锁之后：ReloadEncrypted 要等在途查询退出，
		// 而在途查询正阻塞在 p.mu 上（见 reloadDNSWithCurrentConfig 注释）。
		p.reloadDNSWithCurrentConfig()
	}()

	cfg := p.cfg.Encrypted.ReverseProxy

	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	if req.ClientIPHeader != nil {
		cfg.ClientIPHeader = *req.ClientIPHeader
	}
	if req.TrustedSources != nil {
		sources, err := core.NormalizeTrustedSources(*req.TrustedSources)
		if err != nil {
			return err
		}
		// 全放行是「任何人加了转发头就能冒充白名单成员」，必须显式确认：
		// 界面弹窗只是体验层的拦截，服务端这道才真正挡得住直接调接口的人
		if err := ipc.ValidateACLUnrestricted(sources, req.ConfirmUnrestricted); err != nil {
			return err
		}
		cfg.TrustedSources = sources
	} else if err := ipc.ValidateACLUnrestricted(cfg.TrustedSources, req.ConfirmUnrestricted); err != nil {
		// 只改开关或头名时，已有的列表也要重新过一遍这道闸
		return err
	}

	p.cfg.Encrypted.ReverseProxy = cfg
	p.persistConfigLocked("反向代理可信来源")
	// 可信列表在构建 EncryptedServerConfig 时被固化进监听器，必须重建（在 defer 中解锁后执行）
	return nil
}
