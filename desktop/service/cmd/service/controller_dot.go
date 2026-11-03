package main

import (
	"log"

	"github.com/haoze-evolluling/diting/server/internal/core"
	ditingdns "github.com/haoze-evolluling/diting/server/internal/dns"
)

// dotALPN 为 DoT 的 ALPN 标识（RFC 7858 §3.1）。
//
// 不宣告它客户端一样能连——DoT 客户端普遍不校验 ALPN——但宣告之后，误把
// DoH/DoQ 指向这个端口的客户端会握不上手，比连上来再收到解析失败更容易定位。
//
// DoH 的 ALPN（h2）由服务器自己覆写：一张证书要同时服务两种协议时，
// 靠这里传入的 NextProtos 是分不开的。
var dotALPN = []string{"dot"}

// buildEncryptedServerConfig 按当前配置装配加密监听参数。
//
// 调用方需持有 p.mu。返回 nil 表示本次不开放任何加密入口——此时连证书都
// 不去取，免得在用户没开这个功能时因为证书缺失而刷出无意义的错误日志。
func (p *program) buildEncryptedServerConfig() *ditingdns.EncryptedServerConfig {
	enc := p.cfg.Encrypted
	if !enc.Enabled || (!enc.DoTEnabled && !enc.DoHEnabled && !enc.DoQEnabled) {
		return nil
	}
	if p.certManager == nil {
		log.Println("[加密DNS] 证书管理器未就绪，本次不开放加密监听")
		return nil
	}

	tlsCfg, err := p.certManager.TLSConfig(dotALPN...)
	if err != nil {
		// 证书不可用时宁可不监听：没有证书的加密端口只会让客户端
		// 卡在握手阶段，比明确拒服务更难排查
		log.Printf("[加密DNS] 服务端证书不可用，本次不开放加密监听: %v\n", err)
		return nil
	}

	cfg := &ditingdns.EncryptedServerConfig{
		DoTEnabled:    enc.DoTEnabled,
		DoHEnabled:    enc.DoHEnabled,
		DoQEnabled:    enc.DoQEnabled,
		ListenAddress: enc.ListenAddress,
		DoTPort:       enc.DoTPort,
		DoHPort:       enc.DoHPort,
		DoQPort:       enc.DoQPort,
		DoHPath:       enc.DoHPath,
		ServerName:    enc.ServerName,
		TLSConfig:     tlsCfg,
		ReadTimeout:   ditingdns.DefaultDoTReadTimeout,
		IdleTimeout:   ditingdns.DefaultDoTIdleTimeout,
	}

	// 可信代理解析失败时退回「不信任任何转发头」而不是拒绝监听：
	// 两种做法都杜绝了来源伪造，但后者会连带把整个加密入口拖下水。
	// 列表在保存时已校验过，走到这里通常意味着配置文件被手工改坏了，
	// 故用 Warn 级别的日志明确点出真实后果。
	if enc.ReverseProxy.Enabled {
		tp, err := ditingdns.NewTrustedProxy(true, enc.ReverseProxy.TrustedSources,
			enc.ReverseProxy.ClientIPHeader)
		if err != nil {
			log.Printf("[加密DNS] 反向代理可信来源无效，本次将忽略全部转发头，"+
				"代理后的真实客户端 IP 无法还原: %v\n", err)
		} else {
			cfg.TrustedProxy = tp
		}
	}
	// 只开一项时其余项的端口可能还是零值（旧配置文件缺字段），补齐默认值：
	// 运行期配置的校验只看已启用那几项，但日志与界面都会读这些值
	if !isValidEncPort(cfg.DoTPort) {
		cfg.DoTPort = core.DefaultDoTPort
	}
	if !isValidEncPort(cfg.DoHPort) {
		cfg.DoHPort = core.DefaultDoHPort
	}
	if !isValidEncPort(cfg.DoQPort) {
		cfg.DoQPort = core.DefaultDoQPort
	}
	return cfg
}

// isValidEncPort 判断监听端口是否可用；0 视为非法（见 core.isValidPort 的取舍）
func isValidEncPort(port int) bool {
	return port > 0 && port <= 65535
}

// reloadDNSWithCurrentConfig 热重载加密监听器（调用方不得持有 p.mu）。
//
// 加密监听的配置（端口、证书、服务器名）改动时只启停加密端口（853/443 等），无需重启 53
// 端口明文监听，避免端口绑定冲突或主解析链路瞬断。
//
// 必须先快照配置、释放 p.mu，再执行 ReloadEncrypted：后者会等待在途查询协程退出（最多
// 3s×3），而在途查询的每个中间件 getter 都要拿 p.mu。持锁调用即锁序倒置——配置线程等
// 查询退出、查询线程等 p.mu，只能靠超时打破，每次保存加密设置都会让解析流水线停顿数秒。
func (p *program) reloadDNSWithCurrentConfig() {
	p.mu.Lock()
	running := p.dnsRunning
	srv := p.server
	var encCfg *ditingdns.EncryptedServerConfig
	if running && srv != nil {
		encCfg = p.buildEncryptedServerConfig()
	}
	p.mu.Unlock()

	if !running || srv == nil {
		return
	}
	srv.ReloadEncrypted(encCfg)
}
