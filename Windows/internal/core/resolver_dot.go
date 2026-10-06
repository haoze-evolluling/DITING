package core

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

const (
	dotMaxIdleConnsPerHost = 4
	dotIdleTimeout         = 15 * time.Second
	defaultDoTConnectTimeout = 3 * time.Second
	defaultDoTQueryTimeout   = 5 * time.Second
)

type dotConnEntry struct {
	conn     net.Conn
	tlsConn  *tls.Conn
	lastUsed time.Time
	closed   atomic.Bool
}

func (e *dotConnEntry) close() {
	if e == nil || !e.closed.CompareAndSwap(false, true) {
		return
	}
	if e.tlsConn != nil {
		_ = e.tlsConn.Close()
	}
	if e.conn != nil {
		_ = e.conn.Close()
	}
}

func (e *dotConnEntry) isAlive() bool {
	if e == nil || e.closed.Load() || e.conn == nil || e.tlsConn == nil {
		return false
	}
	_ = e.conn.SetReadDeadline(time.Now())
	var b [1]byte
	n, err := e.conn.Read(b[:])
	_ = e.conn.SetReadDeadline(time.Time{})
	if err == nil && n > 0 {
		return false
	}
	if err != nil {
		var netErr net.Error
		if errors.As(err, &netErr) && netErr.Timeout() {
			return true
		}
		return false
	}
	return true
}

// DoTResolver 实现基于 DNS-over-TLS (RFC 7858) 的连接复用解析器
type DoTResolver struct {
	mu           sync.Mutex
	conns        map[string][]*dotConnEntry
	bootstrap    *BootstrapResolver
	sessionCache tls.ClientSessionCache
	customTLS    *tls.Config
	closed       atomic.Bool
}

// NewDoTResolver 创建 DoT 解析器实例
func NewDoTResolver(bootstrap *BootstrapResolver) *DoTResolver {
	return &DoTResolver{
		conns:        make(map[string][]*dotConnEntry),
		bootstrap:    bootstrap,
		sessionCache: tls.NewLRUClientSessionCache(64),
	}
}

// SetTLSConfig 设置自定义 TLS 配置（供测试或自签名根证书注入使用）
func (d *DoTResolver) SetTLSConfig(cfg *tls.Config) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.customTLS = cfg
}

// SetBootstrap 更新引导解析器引用
func (d *DoTResolver) SetBootstrap(bootstrap *BootstrapResolver) {
	d.mu.Lock()
	d.bootstrap = bootstrap
	d.mu.Unlock()
}

// Exchange 发送 DNS 查询至 DoT 服务器并接收响应
func (d *DoTResolver) Exchange(ctx context.Context, rawQuery []byte, server string) ([]byte, error) {
	if d.closed.Load() {
		return nil, fmt.Errorf("dot resolver is closed")
	}

	host := server
	port := "853"
	if h, p, err := net.SplitHostPort(server); err == nil {
		host = h
		port = p
	}

	d.mu.Lock()
	bootstrap := d.bootstrap
	d.mu.Unlock()

	dialCtx, cancel := context.WithTimeout(ctx, defaultDoTConnectTimeout)
	defer cancel()

	targetHost := host
	if bootstrap != nil && bootstrap.IsEnabled() {
		if resolvedIP, rErr := bootstrap.ResolveHost(dialCtx, host); rErr == nil && resolvedIP != "" {
			targetHost = resolvedIP
		}
	}
	targetServer := net.JoinHostPort(targetHost, port)

	entry := d.popIdleConn(targetServer)
	var resp []byte
	var err error

	// 若存在空闲连接，先尝试复用
	if entry != nil {
		probeCtx, probeCancel := context.WithTimeout(ctx, 2*time.Second)
		resp, err = d.executeDoTQuery(probeCtx, entry, rawQuery)
		probeCancel()

		if err != nil || ctx.Err() != nil {
			entry.close()
			entry = nil
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
		}
	}

	// 空闲连接不可用或复用失败，发起全新连接
	if entry == nil && ctx.Err() == nil {
		entry, err = d.dialFreshConn(ctx, host, targetServer)
		if err != nil {
			return nil, err
		}
		resp, err = d.executeDoTQuery(ctx, entry, rawQuery)
	}

	if ctx.Err() != nil {
		if entry != nil {
			entry.close()
		}
		return nil, ctx.Err()
	}

	if err != nil {
		if entry != nil {
			entry.close()
		}
		return nil, err
	}

	d.putIdleConn(targetServer, entry)
	return resp, nil
}

func (d *DoTResolver) popIdleConn(targetServer string) *dotConnEntry {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.closed.Load() || d.conns == nil {
		return nil
	}

	entries := d.conns[targetServer]
	for len(entries) > 0 {
		lastIdx := len(entries) - 1
		c := entries[lastIdx]
		entries = entries[:lastIdx]
		d.conns[targetServer] = entries

		if !c.closed.Load() && time.Since(c.lastUsed) <= dotIdleTimeout && c.isAlive() {
			return c
		}
		c.close()
	}
	return nil
}

func (d *DoTResolver) putIdleConn(targetServer string, c *dotConnEntry) {
	if c == nil {
		return
	}
	if d.closed.Load() || c.closed.Load() {
		c.close()
		return
	}

	d.mu.Lock()
	defer d.mu.Unlock()
	if d.closed.Load() || d.conns == nil {
		c.close()
		return
	}

	entries := d.conns[targetServer]
	if len(entries) < dotMaxIdleConnsPerHost {
		c.lastUsed = time.Now()
		d.conns[targetServer] = append(entries, c)
	} else {
		c.close()
	}
}

func (d *DoTResolver) dialFreshConn(ctx context.Context, host, targetServer string) (*dotConnEntry, error) {
	dialCtx, cancel := context.WithTimeout(ctx, defaultDoTConnectTimeout)
	defer cancel()

	dialer := &net.Dialer{Timeout: defaultDoTConnectTimeout}
	conn, err := dialer.DialContext(dialCtx, "tcp", targetServer)
	if err != nil {
		return nil, fmt.Errorf("dot tcp dial %s: %w", targetServer, err)
	}

	d.mu.Lock()
	var tlsConfig *tls.Config
	if d.customTLS != nil {
		tlsConfig = d.customTLS.Clone()
	} else {
		tlsConfig = &tls.Config{}
	}
	d.mu.Unlock()

	tlsConfig.ServerName = host
	if tlsConfig.MinVersion == 0 {
		tlsConfig.MinVersion = tls.VersionTLS12
	}
	if tlsConfig.ClientSessionCache == nil {
		tlsConfig.ClientSessionCache = d.sessionCache
	}

	tlsConn := tls.Client(conn, tlsConfig)

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(defaultDoTQueryTimeout)) {
		deadline = time.Now().Add(defaultDoTQueryTimeout)
	}
	_ = tlsConn.SetDeadline(deadline)

	if err := tlsConn.HandshakeContext(ctx); err != nil {
		_ = tlsConn.Close()
		_ = conn.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("dot tls handshake %s: %w", host, err)
	}

	return &dotConnEntry{
		conn:     conn,
		tlsConn:  tlsConn,
		lastUsed: time.Now(),
	}, nil
}

func (d *DoTResolver) executeDoTQuery(ctx context.Context, entry *dotConnEntry, rawQuery []byte) ([]byte, error) {
	if entry == nil || entry.closed.Load() || entry.tlsConn == nil {
		return nil, fmt.Errorf("dot connection is closed or nil")
	}

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(defaultDoTQueryTimeout)) {
		deadline = time.Now().Add(defaultDoTQueryTimeout)
	}
	_ = entry.tlsConn.SetDeadline(deadline)

	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(rawQuery)))

	if _, err := entry.tlsConn.Write(append(lenBuf, rawQuery...)); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("dot write: %w", err)
	}

	if _, err := io.ReadFull(entry.tlsConn, lenBuf); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("dot read length: %w", err)
	}

	respLen := binary.BigEndian.Uint16(lenBuf)
	if respLen < 12 || respLen > 65535 {
		return nil, fmt.Errorf("dot invalid response length: %d", respLen)
	}

	respBuf := make([]byte, respLen)
	if _, err := io.ReadFull(entry.tlsConn, respBuf); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("dot read response: %w", err)
	}

	return respBuf, nil
}

// Close 关闭所有空闲 TLS 连接
func (d *DoTResolver) Close() error {
	if !d.closed.CompareAndSwap(false, true) {
		return nil
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, entries := range d.conns {
		for _, e := range entries {
			e.close()
		}
	}
	d.conns = make(map[string][]*dotConnEntry)
	return nil
}
