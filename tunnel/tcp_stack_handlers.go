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

// Default flow handlers for TcpIpStack: each terminated TCP/UDP flow is
// dialed out to the real destination via a socket-protected dialer (so the
// socket doesn't loop back into the VPN) and bytes are relayed.

const (
	flowDialTimeout = 10 * time.Second
)

// newProtectedTcpHandler returns a TcpFlowHandler that forwards the
// TCP flow to its real destination with socket protection. protectFn
// may be nil in standalone / non-VPN scenarios.
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

		// No absolute deadline — rely on tun2socks' TCP keepalive
		// (60s idle / 30s interval / 9 probes) to clean up stuck
		// connections. Hard deadlines killed long-lived streams.
		bidiCopyFlow(conn, remote)
	}
}

// newProtectedUdpHandler returns a UdpFlowHandler that proxies the UDP flow
// directly to its destination: it reads inbound datagrams from the stack,
// forwards them to the real server, and writes responses back. QUIC (UDP 443)
// may need special handling later (per-app blocking or DTLS termination); for
// now everything is forwarded.
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

// protectedControl returns a net.Dialer.Control function that invokes
// the VpnService.protect() fd callback before the outbound connection
// is established, ensuring the socket doesn't itself get routed back
// into the VPN. Returns nil when protectFn is nil (standalone mode).
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

// bidiCopyFlow copies bytes in both directions between two net.Conns and
// returns when both directions have finished. Uses TCP half-close semantics
// where available so a FIN on one direction does not abort the opposite
// direction mid-stream.
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

// relayUDPFlow relays datagrams bidirectionally between two UDP net.Conns.
// Unlike TCP streams, UDP datagrams have no FIN or EOF semantics; without an
// idle read deadline, io.Copy blocks forever, permanently leaking goroutines
// and file descriptors. relayUDPFlow applies a rolling idle deadline on each
// read/write and explicitly terminates both sides when idle or errored.
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
