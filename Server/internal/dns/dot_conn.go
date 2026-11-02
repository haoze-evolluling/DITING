package dns

import (
	"crypto/tls"
	"net"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// dotConn 是 DoT 单连接上的 dns.ResponseWriter 实现。
//
// 之所以不用 miekg/dns 自带的 `Server{Net: "tcp-tls"}`：那条路径虽然也通过
// ConnectionStater 暴露握手状态，但底层连接被包在它自己的 response 结构里，
// 取不到 SNI，也就无法按 `<ClientID>.<服务器名>` 识别客户端。自己实现这个
// 接口后，ServerName 在连接建立的那一刻就能拿到。
//
// 与 TCP 一样，一条连接上可以串行承载多个查询（RFC 7858 §3.1），因此这里
// 按查询循环读，而不是一问一答就断开——客户端每次重连都要重做一次 TLS
// 握手，那样代价太高。
type dotConn struct {
	conn *tls.Conn
	srv  *Server

	// 握手时定下的服务器名，供 DoT 识别 ClientID
	serverName string

	// 一条连接上串行处理查询，写出不会交错；加锁是因为 Close 可能来自
	// 关闭流程，需要与写出互斥
	writeMu sync.Mutex
	closed  bool

	// writeTimeout 是单次写出的期限。TCP 零窗口客户端会让 Write 永久阻塞，
	// 没有期限时一条连接就能钉住一个协程与整条流水线状态
	writeTimeout time.Duration
}

// NewDoTConn 以已完成的 TLS 连接构造 DoT 响应写入器。
//
// 返回具体类型而非 dns.ResponseWriter：调用方还需要 ServerName 与 serve，
// 这两个不在 ResponseWriter 接口上。它仍然满足该接口，可直接交给流水线。
func NewDoTConn(conn *tls.Conn, srv *Server) *dotConn {
	d := &dotConn{conn: conn, srv: srv}
	if conn != nil {
		d.serverName = conn.ConnectionState().ServerName
	}
	return d
}

// LocalAddr 返回本端地址
func (d *dotConn) LocalAddr() net.Addr { return d.conn.LocalAddr() }

// RemoteAddr 返回对端地址
func (d *dotConn) RemoteAddr() net.Addr { return d.conn.RemoteAddr() }

// ServerName 返回客户端握手中给出的 SNI；未提供时为空串
func (d *dotConn) ServerName() string { return d.serverName }

// WriteMsg 封装并写出应答
func (d *dotConn) WriteMsg(m *dns.Msg) error {
	if m == nil {
		return nil
	}
	data, err := m.Pack()
	if err != nil {
		return err
	}
	// 长度前缀会占 2 字节，超长消息无法用 uint16 表达
	if len(data) > dns.MaxMsgSize {
		return dns.ErrBuf
	}
	_, err = d.Write(data)
	return err
}

// Write 写出已封装的消息，并补上 DNS over TCP 的 2 字节长度前缀
func (d *dotConn) Write(b []byte) (int, error) {
	if len(b) > dns.MaxMsgSize {
		return 0, dns.ErrBuf
	}

	framed := make([]byte, 2+len(b))
	framed[0] = byte(len(b) >> 8)
	framed[1] = byte(len(b))
	copy(framed[2:], b)

	d.writeMu.Lock()
	defer d.writeMu.Unlock()
	if d.closed {
		// 连接已关，静默丢弃：调用方是流水线，拿到这个错误也无从补救，
		// 而返回错误会让上层再走一遍 dns.HandleFailed 的写出路径
		return 0, nil
	}
	if d.writeTimeout > 0 {
		// 写期限与读期限相互独立：读完立即设写期限，写完再交还给读循环
		_ = d.conn.SetWriteDeadline(time.Now().Add(d.writeTimeout))
	}
	n, err := d.conn.Write(framed)
	if err != nil {
		return 0, err
	}
	// 报告应用层字节数，与 net.Conn.Write 的语义保持一致
	if n < 2 {
		return 0, nil
	}
	return n - 2, nil
}

// Close 关闭底层连接
func (d *dotConn) Close() error {
	d.writeMu.Lock()
	if d.closed {
		d.writeMu.Unlock()
		return nil
	}
	d.closed = true
	d.writeMu.Unlock()
	return d.conn.Close()
}

// TsigStatus 返回 TSIG 校验状态；DoT 入口不做 TSIG 校验
func (d *dotConn) TsigStatus() error { return nil }

// TsigTimersOnly 设置 TSIG 计时器模式；DoT 入口不做 TSIG 校验
func (d *dotConn) TsigTimersOnly(bool) {}

// Hijack 交还连接控制权；本实现不对外暴露底层连接，故为空操作
func (d *dotConn) Hijack() {}

// serve 在一条已握手的 DoT 连接上读取并处理查询，直到超时、出错或服务关闭。
//
// 返回前一定关闭连接：握手成功的 TLS 连接若只等 GC 回收，服务重启后会留下
// 一批半开的 socket。
func (d *dotConn) serve(readTimeout, idleTimeout time.Duration) {
	defer d.Close()

	timeout := readTimeout
	for d.srv.serving() {
		// 上一次写出会留下写期限；读之前必须清掉，否则空闲等待也会被写期限打断
		_ = d.conn.SetWriteDeadline(time.Time{})
		if err := d.conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
			return
		}

		req, err := d.readMsg()
		if err != nil {
			return
		}
		// 第一条查询用读超时，其后转为更长的空闲超时：客户端保持长连接
		// 的成本不该与它主动发起查询时一样高
		timeout = idleTimeout

		d.srv.handleEncryptedQuery(d, req, queryOrigin{Protocol: "tcp-tls", ServerName: d.serverName})
	}
}

// readMsg 读取一条带长度前缀的 DNS 消息
func (d *dotConn) readMsg() (*dns.Msg, error) {
	// 只借 dns.Conn 的 TCP 分帧（2 字节长度前缀 + io.ReadFull），
	// 不借它之上的读写状态
	return (&dns.Conn{Conn: d.conn}).ReadMsg()
}
