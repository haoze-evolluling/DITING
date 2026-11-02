package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"reflect"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/config"
	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/haoze-evolluling/diting/server/internal/ipc"
	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// GetEncryptedDNS 返回加密 DNS 服务的配置、证书摘要与目录
func (p *program) GetEncryptedDNS(ctx context.Context) (*ipc.EncryptedDNSStatusResponse, error) {
	p.mu.Lock()
	cfg := p.cfg.Encrypted
	certMgr := p.certManager
	server := p.server
	p.mu.Unlock()

	var info core.CertInfo
	var health core.CertHealth
	dir := ""
	if certMgr != nil {
		// 每次查询都重载一次：证书文件可能被外部替换，且只有重新载入
		// 才能发现「已过期」这类仅靠缓存对象看不出来的问题
		certMgr.Reload()
		info = certMgr.Info()
		health = certMgr.Health()
		dir = certMgr.Dir()
	}

	// 实际监听地址只能在监听器里问：配置不等于既成事实
	dotListen, dohListen, doqListen := "", "", ""
	if server != nil {
		dotListen = server.DoTListenAddress()
		dohListen = server.DoHListenAddress()
		doqListen = server.DoQListenAddress()
	}

	return &ipc.EncryptedDNSStatusResponse{
		Config:         cfg,
		Cert:           info,
		CertDir:        dir,
		DoTListen:      dotListen,
		DoHListen:      dohListen,
		DoQListen:      doqListen,
		DoHURLs:        p.dohURLs(cfg),
		// 全放行条目即便已确认也要一直提醒：它让访问控制与限速同时失去意义
		UnrestrictedTrust: core.HasUnrestrictedTrust(cfg.ReverseProxy.TrustedSources),
		DefaultDoTPort:    core.DefaultDoTPort,
		DefaultDoHPort:    core.DefaultDoHPort,
		DefaultDoQPort:    core.DefaultDoQPort,
		DefaultDoHPath:    core.DefaultDoHPath,
		CertExpiresSoon:   health.ExpiresSoon,
		CertExpired:       health.Expired,
	}, nil
}

// dohURLs 生成界面可直接复制的 DoH 地址。
//
// 服务器名排在最前：它是证书里唯一的 DNS 名，终端按它连接才不会被
// 证书校验拦下；网卡 IP 只能作为「证书已含该 IP」时的补充。
func (p *program) dohURLs(cfg core.EncryptedDNSConfig) []string {
	hosts := make([]string, 0, 4)
	if name := strings.TrimSpace(cfg.ServerName); name != "" {
		hosts = append(hosts, name)
	}
	if lanAddrs, err := platform.GetLANAddresses(); err == nil {
		hosts = append(hosts, lanAddrs...)
	} else {
		log.Printf("[加密DNS] 获取局域网地址失败，DoH 地址列表可能不完整: %v\n", err)
	}
	return core.DoHURLs(hosts, cfg.DoHPort, cfg.DoHPath)
}

// ConfigureEncryptedDNS 更新加密 DNS 配置并持久化
func (p *program) ConfigureEncryptedDNS(ctx context.Context, req ipc.ConfigureEncryptedDNSRequest) error {
	p.mu.Lock()
	defer func() {
		p.mu.Unlock()
		// 重建监听器必须在解锁之后（见 reloadDNSWithCurrentConfig 注释）
		p.reloadDNSWithCurrentConfig()
	}()

	cfg := p.cfg.Encrypted
	if req.Enabled != nil {
		cfg.Enabled = *req.Enabled
	}
	if req.DoTEnabled != nil {
		cfg.DoTEnabled = *req.DoTEnabled
	}
	if req.DoHEnabled != nil {
		cfg.DoHEnabled = *req.DoHEnabled
	}
	if req.DoQEnabled != nil {
		cfg.DoQEnabled = *req.DoQEnabled
	}
	if req.DDREnabled != nil {
		cfg.DDREnabled = *req.DDREnabled
	}
	if req.ListenAddress != nil {
		cfg.ListenAddress = *req.ListenAddress
	}
	if req.DoTPort != nil {
		cfg.DoTPort = *req.DoTPort
	}
	if req.DoHPort != nil {
		cfg.DoHPort = *req.DoHPort
	}
	if req.DoQPort != nil {
		cfg.DoQPort = *req.DoQPort
	}
	if req.DoHPath != nil {
		cfg.DoHPath = *req.DoHPath
	}
	if req.ServerName != nil {
		cfg.ServerName = *req.ServerName
	}
	if req.Cert != nil {
		cfg.Cert = *req.Cert
	}
	// 归一化会改写越界参数，配置里必须存归一化后的结果，
	// 否则重启后读回的是界面填过的那个非法值
	core.NormalizeEncryptedDNSConfig(&cfg)

	// 证书配置变了才重新载入；没变就不动，免得每次改端口都去
	// 碰一次密钥文件，也免得把一个正在被监听器使用的证书换掉
	if p.certManager != nil && !reflect.DeepEqual(cfg.Cert, p.cfg.Encrypted.Cert) {
		p.certManager.Configure(cfg.Cert)
	}

	// 自签来源未载入时自动确保证书就绪，避免用户开启监听时因证书缺失而无法启动
	if p.certManager != nil && (cfg.Cert.Source == core.CertSourceSelfSigned || cfg.Cert.Source == "") {
		if !p.certManager.Info().Loaded {
			certCfg := cfg.Cert
			if len(certCfg.DNSNames) == 0 && len(certCfg.IPAddresses) == 0 {
				certCfg.DNSNames, certCfg.IPAddresses = core.DeriveCertNames(
					cfg.ServerName, cfg.ListenAddress, nil)
			}
			if _, err := p.certManager.RenewSelfSignedIfNeeded(certCfg); err != nil {
				log.Printf("[加密DNS] 自签证书补齐/续签失败: %v\n", err)
			} else {
				cfg.Cert = p.certManager.GetConfig()
			}
		} else if renewed, err := p.certManager.RenewSelfSignedIfNeeded(cfg.Cert); err != nil {
			log.Printf("[加密DNS] 自签证书续签失败: %v\n", err)
		} else if renewed {
			cfg.Cert = p.certManager.GetConfig()
		}
	}

	p.cfg.Encrypted = cfg
	p.persistConfigLocked("加密 DNS 配置")
	// 端口、证书、服务器名都只在监听器启动时读取一次，改完必须重建才生效（在 defer 中解锁后执行）
	return nil
}

// GenerateEncryptedCert 生成（或按 Force 重新签发）自签证书
func (p *program) GenerateEncryptedCert(ctx context.Context, req ipc.GenerateCertRequest) error {
	p.mu.Lock()
	defer func() {
		p.mu.Unlock()
		// 换了证书就得重握手，且重建必须在解锁之后
		p.reloadDNSWithCurrentConfig()
	}()

	if p.certManager == nil {
		return fmt.Errorf("证书管理器未就绪")
	}

	cfg := p.cfg.Encrypted.Cert
	if req.KeyType != "" {
		cfg.KeyType = req.KeyType
	}
	if req.CommonName != "" {
		cfg.CommonName = req.CommonName
	}
	// 名字列表是整体替换而非合并：传了空列表表示「就用你推导出来的那些」，
	// 而按名合并会让用户没法删掉一个误加的名字
	cfg.DNSNames = req.DNSNames
	cfg.IPAddresses = req.IPAddresses
	if req.ValidDays > 0 {
		cfg.ValidDays = req.ValidDays
	}
	// 生成前补全 SAN：调用方多半只给了服务器名与监听地址
	if len(cfg.DNSNames) == 0 && len(cfg.IPAddresses) == 0 {
		cfg.DNSNames, cfg.IPAddresses = core.DeriveCertNames(
			p.cfg.Encrypted.ServerName, p.cfg.Encrypted.ListenAddress, nil)
	}
	core.NormalizeCertConfig(&cfg)

	var err error
	if req.Force {
		err = p.certManager.RegenerateSelfSigned(cfg)
	} else {
		_, err = p.certManager.EnsureSelfSigned(cfg)
	}
	if err != nil {
		return err
	}

	// 把实际生效的参数写回配置，界面下次打开看到的就是证书的真实内容
	p.cfg.Encrypted.Cert = p.certManager.GetConfig()
	p.persistConfigLocked("加密 DNS 证书")
	// 换了证书就得重握手：已建立的 DoT 连接仍持有旧证书（重建在 defer 中解锁后执行）
	return nil
}

// ImportEncryptedCert 导入一对 PEM 或一个 PKCS#12 容器
func (p *program) ImportEncryptedCert(ctx context.Context, req ipc.ImportCertRequest) error {
	p.mu.Lock()
	defer func() {
		p.mu.Unlock()
		p.reloadDNSWithCurrentConfig()
	}()

	if p.certManager == nil {
		return fmt.Errorf("证书管理器未就绪")
	}

	switch req.Mode {
	case ipc.CertImportModePEM:
		if req.CertPEM == "" || req.KeyPEM == "" {
			return fmt.Errorf("证书与私钥内容都不能为空")
		}
		if err := p.certManager.ImportPEM([]byte(req.CertPEM), []byte(req.KeyPEM)); err != nil {
			return err
		}
	case ipc.CertImportModePKCS12:
		raw, err := base64.StdEncoding.DecodeString(req.Data)
		if err != nil {
			return fmt.Errorf("PKCS#12 内容不是合法的 base64: %w", err)
		}
		if err := p.certManager.ImportPKCS12(raw, req.Password); err != nil {
			return err
		}
	default:
		return fmt.Errorf("不支持的导入方式: %q", req.Mode)
	}

	p.cfg.Encrypted.Cert = p.certManager.GetConfig()
	p.persistConfigLocked("加密 DNS 证书")
	return nil
}

// persistConfigLocked 在持有 p.mu 的前提下落盘配置
func (p *program) persistConfigLocked(what string) {
	if p.configPath == "" {
		return
	}
	if err := config.SaveConfig(p.configPath, p.cfg); err != nil {
		log.Printf("[配置] 持久化%s失败: %v\n", what, err)
	}
}
