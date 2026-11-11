package dns

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
)

// DoQ 的运行期参数（RFC 9250）。
const (
	// doqNoError 是正常结束的 QUIC 应用错误码
	doqNoError = 0
	// doqProtocolError 用于对端违反协议时关闭连接（RFC 9250 §4.3）
	doqProtocolError = 2
	// doqALPN 是 DoQ 唯一允许的 ALPN 标识（RFC 9250 §4.1.1）
	doqALPN = "doq"
	// doqHandshakeTimeout 限制 QUIC 握手
	doqHandshakeTimeout = 10 * time.Second
	// doqIdleTimeout 是连接的最大空闲时长
	doqIdleTimeout = 60 * time.Second
	// doqKeepAlivePeriod 让服务端主动保活，否则 NAT 设备会静默丢弃映射
	doqKeepAlivePeriod = 15 * time.Second
	// doqMaxIncomingStreams 限制单连接并发流数，防止一个客户端耗尽服务端内存
	doqMaxIncomingStreams = 64
)

// DoQListenAddress 返回 DoQ 实际生效的监听地址；未在监听时返回空串。
func (s *Server) DoQListenAddress() string {
	s.mu.Lock()
	dl := s.doq
	s.mu.Unlock()
	if dl == nil || dl.ln == nil {
		return ""
	}
	return dl.ln.Addr().String()
}

// doqListener 承载 DoQ 的 QUIC 监听器与在途连接。
type doqListener struct {
	ln  *quic.Listener
	srv *Server
	wg  sync.WaitGroup

	// 记录在途连接，关闭时逐个断开：QUIC 的监听器关闭不一定能立即终止
	// 已建立的连接，不主动关就会留下无法回收的协程
	mu    sync.Mutex
	conns map[quic.Connection]struct{}
	stop  bool
}

// startDoQLocked 绑定并激活 DoQ 监听器（RFC 9250）。调用方须持有 s.mu。
func (s *Server) startDoQLocked() error {
	cfg := s.encrypted
	if cfg == nil {
		return fmt.Errorf("未启用加密 DNS 监听")
	}
	if cfg.TLSConfig == nil {
		return fmt.Errorf("未载入服务端证书")
	}
	if err := cfg.Validate(); err != nil {
		return err
	}

	tlsCfg := cfg.TLSConfig.Clone()
	// RFC 9250 §4.1.1：DoQ 强制 TLS 1.3 且 ALPN 必须是 doq
	tlsCfg.NextProtos = []string{doqALPN}
	tlsCfg.MinVersion = tls.VersionTLS13

	quicCfg := &quic.Config{
		HandshakeIdleTimeout: doqHandshakeTimeout,
		MaxIdleTimeout:       doqIdleTimeout,
		KeepAlivePeriod:      doqKeepAlivePeriod,
		MaxIncomingStreams:   doqMaxIncomingStreams,
		// 服务端同样不接受 0-RTT：RFC 9250 §4.4 禁止在 DoQ 上使用，
		// 而且 0-RTT 数据可被重放，对解析请求没有意义
		Allow0RTT: false,
	}

	addr := cfg.DoQListenAddress()
	ln, err := quic.ListenAddr(addr, tlsCfg, quicCfg)
	if err != nil {
		return fmt.Errorf("绑定 %s 失败: %w", addr, err)
	}

	dl := &doqListener{ln: ln, srv: s, conns: make(map[quic.Connection]struct{})}
	s.doq = dl
	go dl.acceptLoop()
	return nil
}

// acceptLoop 接受 QUIC 连接，每条连接单独起协程。
func (d *doqListener) acceptLoop() {
	for d.srv.serving() {
		conn, err := d.ln.Accept(d.acceptContext())
		if err != nil {
			if !d.srv.serving() || errors.Is(err, quic.ErrServerClosed) {
				return
			}
			// 服务仍开着却出错（如瞬时句柄耗尽）：稍等再试，直接 continue
			// 会把这个循环变成忙等
			time.Sleep(50 * time.Millisecond)
			continue
		}

		d.wg.Add(1)
		go func() {
			defer d.wg.Done()
			d.handleConn(conn)
		}()
	}
}

// acceptContext 返回可用于阻塞 Accept 的上下文。
//
// Accept 需要一个在服务关闭时被取消的 ctx；没有它，关闭监听器后这个
// 协程会一直卡在 Accept 上。服务 ctx 尚未建立时回落到 Background。
func (d *doqListener) acceptContext() context.Context {
	if ctx := d.srv.ctx; ctx != nil {
		return ctx
	}
	return context.Background()
}

// handleConn 处理一条 QUIC 连接上的所有查询流。
func (d *doqListener) handleConn(conn quic.Connection) {
	if conn == nil {
		return
	}
	if !d.track(conn) {
		// 关闭已经开始，不必再收下这条连接
		_ = conn.CloseWithError(quic.ApplicationErrorCode(doqNoError), "")
		return
	}
	defer func() {
		d.untrack(conn)
		_ = conn.CloseWithError(quic.ApplicationErrorCode(doqNoError), "")
	}()

	for d.srv.serving() {
		stream, err := conn.AcceptStream(d.acceptContext())
		if err != nil {
			// 连接被对端关闭或空闲超时，都是这条连接的终点
			return
		}
		d.wg.Add(1)
		go func() {
			defer d.wg.Done()
			d.handleStream(conn, stream)
		}()
	}
}

// handleStream 在一条流上完成一次查询。
//
// 每条查询独占一条流（RFC 9250 §4.2），因此处理完就关掉写方向，
// 不在这条流上等待下一条查询。
func (d *doqListener) handleStream(conn quic.Connection, stream quic.Stream) {
	dc := NewDoQConn(stream, conn, d.srv)
	defer func() { _ = dc.Close() }()

	if d.srv.closed.Load() {
		return
	}

	timeout := d.srv.queryTimeout()
	if err := stream.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return
	}

	req, err := readDoQQuery(stream)
	if err != nil {
		// 对端没按 RFC 9250 发包：按协议错误关闭整条连接，
		// 只关这条流会让一个跑偏的客户端持续产生无意义的流
		if errors.Is(err, errDoQProtocol) {
			_ = conn.CloseWithError(quic.ApplicationErrorCode(doqProtocolError), err.Error())
			return
		}
		return
	}

	_ = stream.SetWriteDeadline(time.Now().Add(timeout))
	// DoQ 只有 SNI 这一条身份线索：QUIC 上不存在 DoH 那样的路径段，
	// 因此识别规则与 DoT 完全一致
	d.srv.handleEncryptedQuery(dc, req, queryOrigin{
		Protocol:   "doq",
		ServerName: doqServerName(conn),
	})
}

// track 登记一条在途连接；监听器已在关闭中时返回 false。
func (d *doqListener) track(c quic.Connection) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.stop {
		return false
	}
	d.conns[c] = struct{}{}
	return true
}

// untrack 注销一条已结束的连接。
func (d *doqListener) untrack(c quic.Connection) {
	d.mu.Lock()
	delete(d.conns, c)
	d.mu.Unlock()
}

// close 停止接受新连接、断开在途连接，并等待处理协程退出。
func (d *doqListener) close() {
	if d.ln != nil {
		// 用 Accept 的 ctx 取消 + Close 双保险：Close 会拒掉握手中的连接，
		// 而取消 ctx 让已经阻塞在 Accept 上的那个协程立刻返回
		_ = d.ln.Close()
	}

	d.mu.Lock()
	d.stop = true
	pending := make([]quic.Connection, 0, len(d.conns))
	for c := range d.conns {
		pending = append(pending, c)
	}
	d.mu.Unlock()

	// 主动断开而不是等空闲超时：QUIC 的连接要等到 MaxIdleTimeout 才会自己消失
	for _, c := range pending {
		_ = c.CloseWithError(quic.ApplicationErrorCode(doqNoError), "")
	}

	done := make(chan struct{})
	go func() {
		d.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		// 与明文监听器同样的取舍：超时后强行退出，不阻塞整体关闭
	}
}

// errDoQProtocol 标记「对端违反 RFC 9250」这类必须断开连接的读错误。
var errDoQProtocol = errors.New("doq protocol error")

// readDoQQuery 读取一条带 2 字节长度前缀的 DoQ 查询。
//
// 与 DoT 不同，DoQ 要求 Message ID 必须为 0（RFC 9250 §4.2.1）：
// 流本身就是请求与应答的对应关系，非 0 说明对端按别的协议在说话。
func readDoQQuery(r io.Reader) (*dns.Msg, error) {
	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(r, lenBuf); err != nil {
		// 读不到长度前缀多为对端主动关流，属于正常收尾
		return nil, err
	}

	// 上限不必再判：长度前缀是 uint16，最大也就 65535。
	// 这里只需挡住连 12 字节 DNS 头都装不下的值。
	size := int(binary.BigEndian.Uint16(lenBuf))
	if size < 12 {
		return nil, fmt.Errorf("%w: 报文长度 %d 非法", errDoQProtocol, size)
	}

	buf := make([]byte, size)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}

	req := new(dns.Msg)
	if err := req.Unpack(buf); err != nil {
		return nil, fmt.Errorf("%w: 报文无法解析", errDoQProtocol)
	}
	if req.Id != 0 {
		return nil, fmt.Errorf("%w: Message ID 应为 0，实得 %d", errDoQProtocol, req.Id)
	}
	return req, nil
}

// doqServerName 从 QUIC 连接状态里取客户端给出的 SNI。
func doqServerName(conn quic.Connection) string {
	if conn == nil {
		return ""
	}
	return strings.TrimSpace(conn.ConnectionState().TLS.ServerName)
}
