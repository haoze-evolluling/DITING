// tcp_stack_handlers.go provides default protected TCP and UDP flow forwarders for the userspace stack.
//
// Socket Protection & Streaming:
// - Routing Loop Prevention: Uses protectedControl to invoke Android VpnService.protect() before dial out.
// - TCP Half-Close: bidiCopyFlow supports half-close so EOF in one direction does not prematurely terminate reverse traffic.
// - UDP Deadlines: relayUDPFlow enforces rolling idle deadlines to prevent permanent goroutine and file descriptor leaks.

package tunnel

import (
	"fmt"
	"io"
	"net"
	"sync"
	"syscall"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

const (
	flowDialTimeout = 10 * time.Second
)

func newProtectedTcpHandler(uidr UIDResolver, protectFn func(fd int) bool) TcpFlowHandler {
	return func(conn adapter.TCPConn) {
		defer conn.Close()

		flow := tcpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolTCP, flow)

		if flow.serverIP.IsUnspecified() {
			return
		}

		dst := net.JoinHostPort(flow.serverIP.String(), fmt.Sprintf("%d", flow.serverPort))
		dialer := &net.Dialer{
			Timeout: flowDialTimeout,
			Control: protectedControl(protectFn),
		}

		remote, err := dialer.Dial("tcp", dst)
		if err != nil {
			logf("[TcpStack] TCP uid=%d dial %s: %v", uid, dst, err)
			return
		}
		defer remote.Close()

		logf("[TcpStack] TCP uid=%d %s ↔ %s", uid, flow.appIP, dst)

		bidiCopyFlow(conn, remote)
	}
}

func newProtectedUdpHandler(uidr UIDResolver, protectFn func(fd int) bool) UdpFlowHandler {
	return func(conn adapter.UDPConn) {
		defer conn.Close()

		flow := udpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolUDP, flow)

		if flow.serverIP.IsUnspecified() {
			return
		}

		dst := &net.UDPAddr{IP: flow.serverIP, Port: flow.serverPort}
		dialer := &net.Dialer{
			Timeout: flowDialTimeout,
			Control: protectedControl(protectFn),
		}
		remote, err := dialer.Dial("udp", dst.String())
		if err != nil {
			logf("[TcpStack] UDP uid=%d dial %s: %v", uid, dst, err)
			return
		}
		defer remote.Close()

		logf("[TcpStack] UDP uid=%d %s ↔ %s", uid, flow.appIP, dst)

		relayUDPFlow(conn, remote)
	}
}

func protectedControl(protectFn func(fd int) bool) func(network, address string, c syscall.RawConn) error {
	if protectFn == nil {
		return nil
	}
	return func(network, address string, c syscall.RawConn) error {
		return c.Control(func(fd uintptr) {
			protectFn(int(fd))
		})
	}
}

func bidiCopyFlow(a, b net.Conn) {
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		io.Copy(b, a)
		if cw, ok := b.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()
	go func() {
		defer wg.Done()
		io.Copy(a, b)
		if cw, ok := a.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()

	wg.Wait()
}

const defaultUDPIdleTimeout = 30 * time.Second

var udpBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, 65535)
		return &b
	},
}

func relayUDPFlow(a, b net.Conn) {
	done := make(chan struct{}, 2)

	pipe := func(dst, src net.Conn) {
		defer func() { done <- struct{}{} }()
		bufp := udpBufPool.Get().(*[]byte)
		defer udpBufPool.Put(bufp)
		buf := *bufp
		for {
			_ = src.SetReadDeadline(time.Now().Add(defaultUDPIdleTimeout))
			n, err := src.Read(buf)
			if n > 0 {
				_ = dst.SetWriteDeadline(time.Now().Add(defaultUDPIdleTimeout))
				if _, werr := dst.Write(buf[:n]); werr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}

	go pipe(b, a)
	go pipe(a, b)

	<-done
	_ = a.Close()
	_ = b.Close()
	<-done
}
