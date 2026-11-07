// mitm_sniffer.go peeks at initial flow payloads and hands the bytes back to the relay.
//
// Low-Latency Inspection:
// - Performs a single conn.Read (up to 2KB) rather than blocking on bufio.Reader.Peek, returning a replay reader.
// - The bytes are classified by the Rust flow sniffer kernel (rust/diting-sniffer-core): TLS
//   ClientHello SNI, plaintext HTTP Host, or neither. This file only does the Read and the replay.

package tunnel

import (
	"bytes"
	"io"
	"net"
	"sync"
	"time"
)

func peekFlow(conn net.Conn, maxBytes int, timeout time.Duration) ([]byte, io.Reader, error) {
	conn.SetReadDeadline(time.Now().Add(timeout))
	defer conn.SetReadDeadline(time.Time{})

	bufp := peekBufPool.Get().(*[]byte)
	buf := *bufp
	if len(buf) < maxBytes {
		buf = make([]byte, maxBytes)
	}
	buf = buf[:maxBytes]
	n, err := conn.Read(buf)
	if n == 0 {
		peekBufPool.Put(bufp)
		return nil, nil, err
	}
	peeked := make([]byte, n)
	copy(peeked, buf[:n])
	peekBufPool.Put(bufp)
	return peeked, io.MultiReader(bytes.NewReader(peeked), conn), nil
}

var peekBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, peekSize)
		return &b
	},
}

type peekReplayConn struct {
	net.Conn
	r io.Reader
}

func (c *peekReplayConn) Read(b []byte) (int, error) {
	return c.r.Read(b)
}

func intToStr(i int) string {
	if i == 0 {
		return "0"
	}
	var buf [20]byte
	pos := len(buf)
	neg := i < 0
	if neg {
		i = -i
	}
	for i > 0 {
		pos--
		buf[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		buf[pos] = '-'
	}
	return string(buf[pos:])
}
