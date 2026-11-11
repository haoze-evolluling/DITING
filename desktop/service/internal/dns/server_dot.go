package dns

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"
)

// dotHandshakeTimeout 限制单次 TLS 握手；握手不完成就不该一直占着连接
const dotHandshakeTimeout = 10 * time.Second

// DoTListenAddress 返回 DoT 实际生效的监听地址；未在监听时返回空串。
//
// 与配置里的端口分开：配置写着 853 不代表真的绑上了——可能证书载入失败，
// 也可能端口被别人占了。界面要显示的是后者。
func (s *Server) DoTListenAddress() string {
	s.mu.Lock()
	dl := s.dot
	s.mu.Unlock()
	if dl == nil || dl.ln == nil {
		return ""
	}
	return dl.ln.Addr().String()
}

// dotListener 承载 DoT 的 TLS 监听器、accept 循环与在途连接。
//
// 自建 accept 循环而不是交给 miekg/dns 的 "tcp-tls"：需要在握手完成时
// 拿到 SNI 以识别 ClientID，见 dotConn 的说明。
type dotListener struct {
	ln  net.Listener
	srv *Server
	wg  sync.WaitGroup

	// 记录在途连接，关闭时逐个断开：停留在读超时等待中的空闲连接
	// 不在 activeQueries 里，不主动断就会留下半开的 socket
	mu    sync.Mutex
	conns map[*dotConn]struct{}
	stop  bool
}

// startDoTLocked 绑定并激活 DoT 监听器（RFC 7858）。
//
// 绑定失败会如实返回错误，由调用方决定降级还是放弃——加密监听是附加能力，
// 不让它拖垮明文解析的启动。调用方须持有 s.mu。
func (s *Server) startDoTLocked() error {
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

	addr := cfg.DoTListenAddress()
	network := "tcp"
	if isIPv6(addr) {
		network = "tcp6"
	} else {
		network = "tcp4"
	}

	ln, err := net.Listen(network, addr)
	if err != nil {
		return fmt.Errorf("绑定 %s 失败: %w", addr, err)
	}

	dl := &dotListener{
		ln:    tls.NewListener(ln, cfg.TLSConfig),
		srv:   s,
		conns: make(map[*dotConn]struct{}),
	}
	s.dot = dl
	readTimeout := cfg.ReadTimeout
	if readTimeout <= 0 {
		readTimeout = DefaultDoTReadTimeout
	}
	idleTimeout := cfg.IdleTimeout
	if idleTimeout <= 0 {
		idleTimeout = DefaultDoTIdleTimeout
	}
	go dl.acceptLoop(readTimeout, idleTimeout)
	return nil
}

// acceptLoop 接受 DoT 连接，每个连接单独起协程处理。
//
// 退出条件同时看进程级 serving() 与监听器自身的 stop：热重载时旧监听器
// 已被 close，若只看 serving() 就会在已关闭的 listener 上以 20 次/秒空转。
func (d *dotListener) acceptLoop(readTimeout, idleTimeout time.Duration) {
	for d.srv.serving() && !d.isStopped() {
		conn, err := d.ln.Accept()
		if err != nil {
			if !d.srv.serving() || d.isStopped() || errors.Is(err, net.ErrClosed) {
				return
			}
			// 监听器仍开着却出错（如瞬时句柄耗尽）：稍等再试，
			// 直接 continue 会把这个循环变成忙等
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() {
				continue
			}
			time.Sleep(50 * time.Millisecond)
			continue
		}

		tlsConn, ok := conn.(*tls.Conn)
		if !ok {
			_ = conn.Close()
			continue
		}

		d.wg.Add(1)
		go func() {
			defer d.wg.Done()
			d.handleConn(tlsConn, readTimeout, idleTimeout)
		}()
	}
}

// handleConn 完成握手后把连接交给 DoT 读取循环。
func (d *dotListener) handleConn(conn *tls.Conn, readTimeout, idleTimeout time.Duration) {
	ctx := d.srv.ctx
	if ctx == nil {
		ctx = context.Background()
	}

	// 显式握手：只有握手完成才拿得到 SNI。握手上也要有 Deadline，
	// 否则一个只连不握手的对端就能一直占着这个协程。
	hsCtx, cancel := context.WithTimeout(ctx, dotHandshakeTimeout)
	defer cancel()
	if err := conn.HandshakeContext(hsCtx); err != nil {
		_ = conn.Close()
		return
	}
	_ = conn.SetDeadline(time.Time{})

	dc := NewDoTConn(conn, d.srv)
	dc.writeTimeout = readTimeout
	if !d.track(dc) {
		// 关闭已经开始，不必再收下这条连接
		_ = conn.Close()
		return
	}
	defer d.untrack(dc)

	dc.serve(readTimeout, idleTimeout)
}

// isStopped 报告监听器是否已进入关闭流程。
func (d *dotListener) isStopped() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.stop
}

// track 登记一条在途连接；监听器已在关闭中时返回 false。
func (d *dotListener) track(c *dotConn) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.stop {
		return false
	}
	d.conns[c] = struct{}{}
	return true
}

// untrack 注销一条已结束的连接。
func (d *dotListener) untrack(c *dotConn) {
	d.mu.Lock()
	delete(d.conns, c)
	d.mu.Unlock()
}

// close 停止接受新连接、断开在途连接，并等待处理协程退出。
func (d *dotListener) close() {
	_ = d.ln.Close()

	d.mu.Lock()
	d.stop = true
	pending := make([]*dotConn, 0, len(d.conns))
	for c := range d.conns {
		pending = append(pending, c)
	}
	d.mu.Unlock()

	// 主动断开而不是等读超时：空闲连接要等到下一个超时才会发现服务已停
	for _, c := range pending {
		_ = c.Close()
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
