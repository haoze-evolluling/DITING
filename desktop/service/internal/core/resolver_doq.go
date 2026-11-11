package core

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
)

const (
	doqMaxIdleConnsPerHost   = 2
	doqIdleTimeout           = 30 * time.Second
	defaultDoQConnectTimeout = 3 * time.Second
	defaultDoQQueryTimeout   = 5 * time.Second
	doqMaxResponseBytes      = 65535
	doqApplicationErrorNoErr = 0
	doqKeepAlivePeriod       = 10 * time.Second
	doqDefaultPort           = "853"
	doqALPN                  = "doq"
)

// doqConnEntry 表示一条池化的 QUIC 连接。
//
// QUIC 连接本身支持多路复用，同一连接上可并发开启多条 stream，
// 因此这里不像 DoT 那样需要逐查询独占，只需在连接关闭后淘汰即可。
type doqConnEntry struct {
	conn     quic.Connection
	lastUsed time.Time
	closed   atomic.Bool
}

func (e *doqConnEntry) close() {
	if e == nil || !e.closed.CompareAndSwap(false, true) {
		return
	}
	if e.conn != nil {
		_ = e.conn.CloseWithError(doqApplicationErrorNoErr, "")
	}
}

// isAlive 借助 quic.Connection.Context() 判断连接是否仍然存活。
// 该 Context 在连接关闭或超时后会被取消，无需额外探测报文。
func (e *doqConnEntry) isAlive() bool {
	if e == nil || e.closed.Load() || e.conn == nil {
		return false
	}
	select {
	case <-e.conn.Context().Done():
		return false
	default:
		return true
	}
}

// DoQResolver 实现基于 DNS-over-QUIC (RFC 9250) 的连接复用解析器
type DoQResolver struct {
	mu        sync.Mutex
	conns     map[string][]*doqConnEntry
	bootstrap *BootstrapResolver
	customTLS *tls.Config
	pinLookup PinLookup
	closed    atomic.Bool
}

// NewDoQResolver 创建 DoQ 解析器实例
func NewDoQResolver(bootstrap *BootstrapResolver) *DoQResolver {
	return &DoQResolver{
		conns:     make(map[string][]*doqConnEntry),
		bootstrap: bootstrap,
	}
}

// SetTLSConfig 设置自定义 TLS 配置（供测试或自签名根证书注入使用）
func (d *DoQResolver) SetTLSConfig(cfg *tls.Config) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.customTLS = cfg
}

// SetPinLookup 设置按主机名查询的证书固定表，并清理既有连接
// （已建立的连接可能未经过固定校验，必须重建）
func (d *DoQResolver) SetPinLookup(lookup PinLookup) {
	d.mu.Lock()
	d.pinLookup = lookup
	entries := d.drainLocked()
	d.mu.Unlock()
	closeDoQEntries(entries)
}

// SetBootstrap 更新引导解析器引用并清理旧连接
func (d *DoQResolver) SetBootstrap(bootstrap *BootstrapResolver) {
	d.mu.Lock()
	d.bootstrap = bootstrap
	entries := d.drainLocked()
	d.mu.Unlock()
	closeDoQEntries(entries)
}

// Exchange 发送 DNS 查询至 DoQ 服务器并接收响应
func (d *DoQResolver) Exchange(ctx context.Context, rawQuery []byte, server string) ([]byte, error) {
	if d.closed.Load() {
		return nil, fmt.Errorf("doq resolver is closed")
	}

	host := server
	port := doqDefaultPort
	if h, p, err := net.SplitHostPort(server); err == nil {
		host = h
		port = p
	}
	cleanHost := strings.Trim(host, "[]")

	d.mu.Lock()
	bootstrap := d.bootstrap
	d.mu.Unlock()

	// 引导解析：避免为了连上游而依赖系统 DNS，形成解析环路
	targetHost := cleanHost
	if bootstrap != nil && bootstrap.IsEnabled() {
		if resolvedIP, rErr := bootstrap.ResolveHost(ctx, cleanHost); rErr == nil && resolvedIP != "" {
			targetHost = resolvedIP
		}
	}
	targetServer := net.JoinHostPort(strings.Trim(targetHost, "[]"), port)

	entry := d.popIdleConn(targetServer)

	// 若存在空闲连接，先尝试复用；QUIC 连接失效表现为 stream 打开/读写失败
	if entry != nil {
		probeCtx, probeCancel := context.WithTimeout(ctx, 2*time.Second)
		resp, err := d.executeDoQQuery(probeCtx, entry, rawQuery)
		probeCancel()

		if err == nil && ctx.Err() == nil {
			d.putIdleConn(targetServer, entry)
			return resp, nil
		}

		entry.close()
		entry = nil
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
	}

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}

	// 空闲连接不可用，发起全新连接
	entry, err := d.dialFreshConn(ctx, cleanHost, targetServer)
	if err != nil {
		return nil, err
	}

	resp, err := d.executeDoQQuery(ctx, entry, rawQuery)
	if ctx.Err() != nil {
		entry.close()
		return nil, ctx.Err()
	}
	if err != nil {
		entry.close()
		return nil, err
	}

	d.putIdleConn(targetServer, entry)
	return resp, nil
}

func (d *DoQResolver) popIdleConn(targetServer string) *doqConnEntry {
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

		if !c.closed.Load() && time.Since(c.lastUsed) <= doqIdleTimeout && c.isAlive() {
			return c
		}
		c.close()
	}
	return nil
}

func (d *DoQResolver) putIdleConn(targetServer string, c *doqConnEntry) {
	if c == nil {
		return
	}
	if d.closed.Load() || c.closed.Load() || !c.isAlive() {
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
	if len(entries) < doqMaxIdleConnsPerHost {
		c.lastUsed = time.Now()
		d.conns[targetServer] = append(entries, c)
	} else {
		c.close()
	}
}

// drainLocked 清空连接池并返回全部条目，调用方需持有 d.mu
func (d *DoQResolver) drainLocked() []*doqConnEntry {
	var all []*doqConnEntry
	for _, entries := range d.conns {
		all = append(all, entries...)
	}
	d.conns = make(map[string][]*doqConnEntry)
	return all
}

func closeDoQEntries(entries []*doqConnEntry) {
	for _, e := range entries {
		e.close()
	}
}

func (d *DoQResolver) dialFreshConn(ctx context.Context, host, targetServer string) (*doqConnEntry, error) {
	dialCtx, cancel := context.WithTimeout(ctx, defaultDoQConnectTimeout)
	defer cancel()

	d.mu.Lock()
	tlsConfig := PinAwareTLSConfig(d.customTLS, d.pinLookup)
	d.mu.Unlock()

	tlsConfig.ServerName = host
	// RFC 9250 §4.1.1：DoQ 强制 TLS 1.3，且 ALPN 必须为 "doq"
	if tlsConfig.MinVersion == 0 || tlsConfig.MinVersion < tls.VersionTLS13 {
		tlsConfig.MinVersion = tls.VersionTLS13
	}
	if len(tlsConfig.NextProtos) == 0 {
		tlsConfig.NextProtos = []string{doqALPN}
	}

	// 显式禁用 0-RTT：RFC 9250 §4.4 要求客户端不得在 DoQ 上使用 0-RTT，
	// 故这里使用 DialAddr 而非 DialAddrEarly。
	quicCfg := &quic.Config{
		HandshakeIdleTimeout: defaultDoQConnectTimeout,
		MaxIdleTimeout:       doqIdleTimeout,
		KeepAlivePeriod:      doqKeepAlivePeriod,
		Allow0RTT:            false,
	}

	conn, err := quic.DialAddr(dialCtx, targetServer, tlsConfig, quicCfg)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("doq dial %s: %w", targetServer, err)
	}

	return &doqConnEntry{conn: conn, lastUsed: time.Now()}, nil
}

// executeDoQQuery 在一条新建的双向 stream 上完成一次查询。
//
// RFC 9250 §4.2：每条查询独占一条 stream，报文中携带 2 字节长度前缀，
// 且 DNS Message ID 必须置 0（§4.2.1）。
func (d *DoQResolver) executeDoQQuery(ctx context.Context, entry *doqConnEntry, rawQuery []byte) ([]byte, error) {
	if entry == nil || entry.closed.Load() || entry.conn == nil {
		return nil, fmt.Errorf("doq connection is closed or nil")
	}

	payload, err := doqNormalizeQuery(rawQuery)
	if err != nil {
		return nil, err
	}

	stream, err := entry.conn.OpenStreamSync(ctx)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("doq open stream: %w", err)
	}
	defer func() {
		// 半关闭写方向，向对端表明查询已发送完毕
		_ = stream.Close()
	}()

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(defaultDoQQueryTimeout)) {
		deadline = time.Now().Add(defaultDoQQueryTimeout)
	}
	_ = stream.SetDeadline(deadline)

	if _, err := stream.Write(doqFrame(payload)); err != nil {
		stream.CancelRead(doqApplicationErrorNoErr)
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("doq write: %w", err)
	}

	resp, err := doqReadFramedResponse(stream)
	if err != nil {
		stream.CancelRead(doqApplicationErrorNoErr)
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, err
	}

	return resp, nil
}

// doqNormalizeQuery 将查询报文的 Message ID 归零并回填长度前缀。
//
// 报文无法解析时按原样返回，交由对端报错，避免在客户端静默丢弃请求。
func doqNormalizeQuery(rawQuery []byte) ([]byte, error) {
	if len(rawQuery) < 12 {
		return nil, fmt.Errorf("doq query too short: %d bytes", len(rawQuery))
	}

	var msg dns.Msg
	if err := msg.Unpack(rawQuery); err != nil {
		return rawQuery, nil
	}
	if msg.Id == 0 {
		return rawQuery, nil
	}
	msg.Id = 0
	packed, err := msg.Pack()
	if err != nil {
		return rawQuery, nil
	}
	return packed, nil
}

// doqFrame 为报文加上 RFC 9250 要求的 2 字节大端长度前缀
func doqFrame(payload []byte) []byte {
	framed := make([]byte, 2+len(payload))
	binary.BigEndian.PutUint16(framed, uint16(len(payload)))
	copy(framed[2:], payload)
	return framed
}

// doqReadFramedResponse 读取并校验一条带长度前缀的应答报文
func doqReadFramedResponse(stream io.Reader) ([]byte, error) {
	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(stream, lenBuf); err != nil {
		return nil, fmt.Errorf("doq read length: %w", err)
	}

	respLen := binary.BigEndian.Uint16(lenBuf)
	if respLen < 12 || respLen > doqMaxResponseBytes {
		return nil, fmt.Errorf("doq invalid response length: %d", respLen)
	}

	respBuf := make([]byte, respLen)
	if _, err := io.ReadFull(stream, respBuf); err != nil {
		return nil, fmt.Errorf("doq read response: %w", err)
	}

	// 服务端必须将 Message ID 置 0；非 0 说明对端不遵循 RFC 9250
	var respMsg dns.Msg
	if err := respMsg.Unpack(respBuf); err == nil && respMsg.Id != 0 {
		return nil, fmt.Errorf("doq response has non-zero message id: %d", respMsg.Id)
	}

	return respBuf, nil
}

// Close 关闭所有空闲 QUIC 连接
func (d *DoQResolver) Close() error {
	if !d.closed.CompareAndSwap(false, true) {
		return nil
	}
	d.mu.Lock()
	entries := d.drainLocked()
	d.mu.Unlock()
	closeDoQEntries(entries)
	return nil
}
