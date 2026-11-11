package core

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
)

// DoH3Resolver 实现基于 DNS-over-HTTP/3 (RFC 8484 over HTTP/3) 的解析器。
//
// 与 DoHResolver 的区别只在传输层：HTTP/3 走 QUIC，
// 因此在丢包与高时延链路上省去 TCP 队头阻塞，握手也更快。
// 报文编解码、状态码校验等语义完全复用 dohExchangeWithClient。
type DoH3Resolver struct {
	mu         sync.RWMutex
	bootstrap  *BootstrapResolver
	customTLS  *tls.Config
	pinLookup  PinLookup
	httpClient *http.Client
	transport  *http3.Transport
}

// NewDoH3Resolver 创建 DoH3 解析器实例
func NewDoH3Resolver(bootstrap *BootstrapResolver) *DoH3Resolver {
	d := &DoH3Resolver{bootstrap: bootstrap}
	d.rebuildClient()
	return d
}

// SetTLSConfig 设置自定义 TLS 配置（供测试或注入自签名证书使用）
func (d *DoH3Resolver) SetTLSConfig(cfg *tls.Config) {
	d.mu.Lock()
	d.customTLS = cfg
	d.rebuildClientLocked()
	d.mu.Unlock()
}

// SetPinLookup 设置按主机名查询的证书固定表，并重建 HTTP/3 传输层
func (d *DoH3Resolver) SetPinLookup(lookup PinLookup) {
	d.mu.Lock()
	d.pinLookup = lookup
	d.rebuildClientLocked()
	d.mu.Unlock()
}

// SetBootstrap 更新引导解析器并重建 HTTP/3 连接
func (d *DoH3Resolver) SetBootstrap(bootstrap *BootstrapResolver) {
	d.mu.Lock()
	d.bootstrap = bootstrap
	d.rebuildClientLocked()
	d.mu.Unlock()
}

func (d *DoH3Resolver) rebuildClient() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.rebuildClientLocked()
}

// rebuildClientLocked 重建底层 HTTP/3 客户端，调用方需持有 d.mu
func (d *DoH3Resolver) rebuildClientLocked() {
	old := d.transport

	transport := &http3.Transport{
		TLSClientConfig: d.tlsConfigLocked(),
		QUICConfig: &quic.Config{
			HandshakeIdleTimeout: defaultDoHConnectTimeout,
			MaxIdleTimeout:       90 * time.Second,
			KeepAlivePeriod:      10 * time.Second,
		},
		// 与 DoH 的 HTTP/2 客户端一致：引导解析由自定义 Dial 完成，
		// 不依赖系统 DNS，避免形成解析环路。
		Dial: d.dialFuncLocked(),
	}

	d.transport = transport
	d.httpClient = &http.Client{
		Transport: transport,
		Timeout:   defaultDoHQueryTimeout,
	}

	if old != nil {
		// 旧传输层的连接已无引用，异步关闭避免阻塞配置热更新
		go func() { _ = old.Close() }()
	}
}

func (d *DoH3Resolver) tlsConfigLocked() *tls.Config {
	cfg := PinAwareTLSConfig(d.customTLS, d.pinLookup)
	if cfg.MinVersion == 0 {
		cfg.MinVersion = tls.VersionTLS13
	}
	return cfg
}

// dialFuncLocked 构造 QUIC 拨号函数：先把主机名经引导解析为 IP，再建连。
//
// 保留 tlsCfg 中由 http3.Transport 依据 URL 主机名填好的 ServerName，
// 使证书校验仍针对原始域名，而非引导解析得到的 IP。
func (d *DoH3Resolver) dialFuncLocked() func(context.Context, string, *tls.Config, *quic.Config) (quic.EarlyConnection, error) {
	bootstrap := d.bootstrap

	return func(ctx context.Context, addr string, tlsCfg *tls.Config, cfg *quic.Config) (quic.EarlyConnection, error) {
		target := addr
		if bootstrap != nil && bootstrap.IsEnabled() {
			if host, port, err := net.SplitHostPort(addr); err == nil {
				if resolvedIP, rErr := bootstrap.ResolveHost(ctx, host); rErr == nil && resolvedIP != "" {
					target = net.JoinHostPort(strings.Trim(resolvedIP, "[]"), port)
				}
			}
		}

		udpAddr, err := net.ResolveUDPAddr("udp", target)
		if err != nil {
			return nil, fmt.Errorf("doh3 resolve %s: %w", target, err)
		}

		dialCtx, cancel := context.WithTimeout(ctx, defaultDoHConnectTimeout)
		defer cancel()

		udpConn, err := net.ListenUDP("udp", nil)
		if err != nil {
			return nil, fmt.Errorf("doh3 udp listen: %w", err)
		}

		tr := &quic.Transport{Conn: udpConn}
		conn, err := tr.DialEarly(dialCtx, udpAddr, tlsCfg, cfg)
		if err != nil {
			_ = tr.Close()
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			return nil, fmt.Errorf("doh3 dial %s: %w", target, err)
		}
		return conn, nil
	}
}

// Exchange 发送 wire 格式 DNS 查询至 DoH3 服务器并返回响应体
func (d *DoH3Resolver) Exchange(ctx context.Context, rawQuery []byte, dohURL string) ([]byte, error) {
	if strings.TrimSpace(dohURL) == "" {
		return nil, fmt.Errorf("empty doh3 url")
	}

	d.mu.RLock()
	client := d.httpClient
	d.mu.RUnlock()

	if client == nil {
		return nil, fmt.Errorf("doh3 client is not initialized")
	}

	return dohExchangeWithClient(ctx, client, rawQuery, dohURL)
}

// Close 关闭 HTTP/3 传输层及其全部 QUIC 连接
func (d *DoH3Resolver) Close() error {
	d.mu.Lock()
	transport := d.transport
	client := d.httpClient
	d.transport = nil
	d.httpClient = nil
	d.mu.Unlock()

	if client != nil {
		client.CloseIdleConnections()
	}
	if transport != nil {
		return transport.Close()
	}
	return nil
}
