// tcp_stack_handlers.go provides the protected socket control, TCP copy and UDP relay helpers used by the flow handlers.
//
// Socket Protection & Streaming:
// - Routing Loop Prevention: Uses protectedControl to invoke Android VpnService.protect() before dial out.
// - TCP Half-Close: bidiCopyFlow supports half-close so EOF in one direction does not prematurely terminate reverse traffic.
// - UDP Deadlines: relayUDPFlow enforces rolling idle deadlines to prevent permanent goroutine and file descriptor leaks.

package tunnel

import (
	"io"
	"net"
	"sync"
	"syscall"
	"time"

)

const (
	flowDialTimeout = 10 * time.Second
)

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
		copyPooled(b, a)
		if cw, ok := b.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()
	go func() {
		defer wg.Done()
		copyPooled(a, b)
		if cw, ok := a.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()

	wg.Wait()
}

const tcpCopyBufferSize = 32 * 1024

var tcpCopyBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, tcpCopyBufferSize)
		return &b
	},
}

// Hiding ReadFrom/WriteTo forces io.CopyBuffer onto the pooled buffer. One side
// of every relay is a gVisor conn, so the kernel splice fast path never applies
// and net.TCPConn's fallback would allocate a fresh 32 KB buffer per direction.
type copyWriterOnly struct{ io.Writer }
type copyReaderOnly struct{ io.Reader }

func copyPooled(dst io.Writer, src io.Reader) (int64, error) {
	bufp := tcpCopyBufPool.Get().(*[]byte)
	defer tcpCopyBufPool.Put(bufp)
	return io.CopyBuffer(copyWriterOnly{dst}, copyReaderOnly{src}, *bufp)
}

const defaultUDPIdleTimeout = 30 * time.Second

// udpDeadlineRefresh bounds how often the rolling idle deadline is re-armed.
// Re-arming on every datagram cost a timer reset per packet on QUIC-heavy flows;
// the effective idle timeout stays within [timeout-refresh, timeout].
const udpDeadlineRefresh = time.Second

// udpRelayBufSize is the per-direction UDP relay buffer. QUIC and DNS/EDNS
// datagrams are well under it; only IP-fragmented datagrams above 16 KiB
// (rare on mobile paths, and fragmentation is usually filtered) would be
// truncated. 64 KiB per direction per flow pinned ~128 KiB per QUIC flow.
const udpRelayBufSize = 16 * 1024

var udpBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, udpRelayBufSize)
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
		var readArmed, writeArmed time.Time
		for {
			if now := time.Now(); now.Sub(readArmed) >= udpDeadlineRefresh {
				_ = src.SetReadDeadline(now.Add(defaultUDPIdleTimeout))
				readArmed = now
			}
			n, err := src.Read(buf)
			if n > 0 {
				if now := time.Now(); now.Sub(writeArmed) >= udpDeadlineRefresh {
					_ = dst.SetWriteDeadline(now.Add(defaultUDPIdleTimeout))
					writeArmed = now
				}
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
