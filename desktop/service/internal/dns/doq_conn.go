package dns

import (
	"net"
	"sync"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
)

// doqConn 是 DoQ 单条流上的 dns.ResponseWriter 实现。
//
// 与 DoT 的 dotConn 不同，每条查询独占一条流（RFC 9250 §4.2），
// 因此这里不需要读循环，也不需要为串行写出加锁——但 Close 仍可能与写出
// 并发（服务关闭时取消流），所以写出路径上还是要有一把锁。
type doqConn struct {
	stream quic.Stream
	conn   quic.Connection
	srv    *Server

	writeMu sync.Mutex
	closed  bool
}

// NewDoQConn 以一条已建立的 QUIC 双向流构造 DoQ 响应写入器。
func NewDoQConn(stream quic.Stream, conn quic.Connection, srv *Server) *doqConn {
	return &doqConn{stream: stream, conn: conn, srv: srv}
}

// LocalAddr 返回本端地址；流本身不持有地址，取自其所属连接
func (d *doqConn) LocalAddr() net.Addr {
	if d.conn == nil {
		return nil
	}
	return d.conn.LocalAddr()
}

// RemoteAddr 返回对端地址，供访问控制与限速使用
func (d *doqConn) RemoteAddr() net.Addr {
	if d.conn == nil {
		return nil
	}
	return d.conn.RemoteAddr()
}

// WriteMsg 封装并写出应答。
//
// RFC 9250 §4.2.1 要求 DoQ 报文两端的 Message ID 都为 0：流本身就是请求与
// 应答的对应关系，ID 没有存在意义，非 0 反而会被对端判为协议错误。
func (d *doqConn) WriteMsg(m *dns.Msg) error {
	if m == nil {
		return nil
	}
	msg := m
	if msg.Id != 0 {
		msg = m.Copy()
		msg.Id = 0
	}
	data, err := msg.Pack()
	if err != nil {
		return err
	}
	if len(data) > dns.MaxMsgSize {
		return dns.ErrBuf
	}
	_, err = d.Write(data)
	return err
}

// Write 写出已封装的消息，并补上 DoQ 的 2 字节长度前缀
func (d *doqConn) Write(b []byte) (int, error) {
	if len(b) > dns.MaxMsgSize {
		return 0, dns.ErrBuf
	}
	if d.stream == nil {
		return 0, dns.ErrBuf
	}

	framed := make([]byte, 2+len(b))
	framed[0] = byte(len(b) >> 8)
	framed[1] = byte(len(b))
	copy(framed[2:], b)

	d.writeMu.Lock()
	defer d.writeMu.Unlock()
	if d.closed {
		// 与 dotConn 同样的取舍：流已关，静默丢弃，避免上层再走一遍
		// HandleFailed 的写出路径
		return 0, nil
	}
	n, err := d.stream.Write(framed)
	if err != nil {
		return 0, err
	}
	// 报告应用层字节数，与 net.Conn.Write 的语义保持一致
	if n < 2 {
		return 0, nil
	}
	return n - 2, nil
}

// Close 关闭流的写方向并放弃读方向。
//
// 不用 CloseWithError：每个查询流正常结束后都应干净关闭，带着错误码关闭
// 会让对端把一次普通超时也记成协议问题。
func (d *doqConn) Close() error {
	d.writeMu.Lock()
	if d.closed {
		d.writeMu.Unlock()
		return nil
	}
	d.closed = true
	d.writeMu.Unlock()

	if d.stream == nil {
		return nil
	}
	d.stream.CancelRead(quic.StreamErrorCode(doqNoError))
	return d.stream.Close()
}

// TsigStatus 返回 TSIG 校验状态；DoQ 入口不做 TSIG 校验
func (d *doqConn) TsigStatus() error { return nil }

// TsigTimersOnly 设置 TSIG 计时器模式；DoQ 入口不做 TSIG 校验
func (d *doqConn) TsigTimersOnly(bool) {}

// Hijack 交还连接控制权；本实现不对外暴露底层流，故为空操作
func (d *doqConn) Hijack() {}
