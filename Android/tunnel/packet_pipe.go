// packet_pipe.go implements a bounded, bidirectional in-memory packet pipe bridging the TUN interceptor
// and the userspace gVisor TCP/IP stack.
//
// Concurrency & Teardown Design:
// - Ownership: DnsInterceptor retains exclusive read access to the TUN fd, pushing non-DNS packets into the pipe.
// - Backpressure & Loss: Enforces bounded queues; overflows drop packets silently, relying on TCP retransmissions.
// - Panic-Free Shutdown: Uses atomic flags and sync.Once to unblock pending Read and Pop operations without closing
//   active data channels, eliminating send-on-closed-channel panics.

package tunnel

import (
	"io"
	"sync"
	"sync/atomic"
)

const (
	packetQueueDepth = 1024
)

type packetPipe struct {
	inbound  chan *pipeBuffer
	outbound chan *pipeBuffer

	done     chan struct{}
	doneOnce sync.Once

	inboundDropped  atomic.Int64
	outboundDropped atomic.Int64
	outboundWritten atomic.Int64
}

func newPacketPipe() *packetPipe {
	return &packetPipe{
		inbound:  make(chan *pipeBuffer, packetQueueDepth),
		outbound: make(chan *pipeBuffer, packetQueueDepth),
		done:     make(chan struct{}),
	}
}

const pipePooledMaxPacketBytes = 2 * defaultTunMTU

// pipeBuffer wraps pooled packet storage so the pool holds a pointer. Storing
// bare []byte values forces an interface-box allocation on every Get/Put.
type pipeBuffer struct {
	b []byte
}

var pipePacketPool = sync.Pool{
	New: func() any {
		return &pipeBuffer{b: make([]byte, defaultTunMTU)}
	},
}

func pipeBufGet(size int) *pipeBuffer {
	pb := pipePacketPool.Get().(*pipeBuffer)
	if cap(pb.b) < size {
		pb.b = make([]byte, size)
	} else {
		pb.b = pb.b[:size]
	}
	return pb
}

// pipeBufPut recycles a buffer unless it is outside the pooled size class
// (smaller than one MTU or grown past the pool maximum); the GC reclaims those.
func pipeBufPut(pb *pipeBuffer) {
	if cap(pb.b) > pipePooledMaxPacketBytes || cap(pb.b) < defaultTunMTU {
		return
	}
	pipePacketPool.Put(pb)
}

func (p *packetPipe) Read(buf []byte) (int, error) {
	select {
	case pkt := <-p.inbound:
		n := copy(buf, pkt.b)
		pipeBufPut(pkt)
		return n, nil
	case <-p.done:
		return 0, io.EOF
	}
}

func (p *packetPipe) Write(buf []byte) (int, error) {
	var pkt *pipeBuffer
	if len(buf) <= pipePooledMaxPacketBytes {
		pkt = pipeBufGet(len(buf))
		copy(pkt.b, buf)
	} else {
		// Oversized packets bypass the pool: their buffers are not recycled.
		pkt = &pipeBuffer{b: make([]byte, len(buf))}
		copy(pkt.b, buf)
	}

	select {
	case <-p.done:
		pipeBufPut(pkt)
		return len(buf), nil
	default:
	}
	select {
	case p.outbound <- pkt:
		c := p.outboundWritten.Add(1)
		if c <= 5 {
			logf("packetPipe: outbound write #%d (size=%d)", c, len(buf))
		}
	case <-p.done:
		pipeBufPut(pkt)
	default:
		pipeBufPut(pkt)

		c := p.outboundDropped.Add(1)
		if c <= 3 {
			logf("packetPipe: outbound DROPPED #%d (queue full, size=%d)", c, len(buf))
		}
	}
	return len(buf), nil
}

func (p *packetPipe) Push(pkt []byte) {
	select {
	case <-p.done:
		return
	default:
	}

	var buf *pipeBuffer
	if len(pkt) <= pipePooledMaxPacketBytes {
		buf = pipeBufGet(len(pkt))
		copy(buf.b, pkt)
	} else {
		// Oversized packets bypass the pool: their buffers are not recycled.
		buf = &pipeBuffer{b: make([]byte, len(pkt))}
		copy(buf.b, pkt)
	}

	select {
	case p.inbound <- buf:
	case <-p.done:
		pipeBufPut(buf)
	default:
		pipeBufPut(buf)

		c := p.inboundDropped.Add(1)
		if c <= 3 {
			logf("packetPipe: inbound DROPPED #%d (queue full, size=%d)", c, len(pkt))
		}
	}
}

func (p *packetPipe) Pop() *pipeBuffer {
	select {
	case pkt := <-p.outbound:
		return pkt
	case <-p.done:
		return nil
	}
}

func (p *packetPipe) Close() {
	p.doneOnce.Do(func() { close(p.done) })
}
