// tun_link_endpoint.go is the gVisor link endpoint used by the full-tunnel data plane.
//
// It replaces tun2socks' iobased endpoint, removing per-packet work:
// - Inbound: iobased allocated a fresh MTU-sized []byte for every packet read from the TUN. This
//   endpoint reads into one reused buffer (the read loop is single-threaded) and copies the bytes
//   into a gVisor pooled chunk, so steady-state reads allocate nothing on the Go heap.
// - Outbound: iobased cloned each packet into a channel, had a second goroutine clone it again
//   (ToBuffer), Flatten it into a new slice, and then bufferedTun copied it once more. Here the
//   packet views are copied once, straight into a pooled bufferedTun buffer, on the caller's
//   goroutine. bufferedTun keeps its non-blocking queue, drop-on-overflow and retry semantics.

package tunnel

import (
	"sync"

	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

type tunLinkEndpoint struct {
	tun *bufferedTun

	mu         sync.RWMutex
	dispatcher stack.NetworkDispatcher
	mtu        uint32

	startOnce sync.Once
	wg        sync.WaitGroup
}

func newTunLinkEndpoint(tun *bufferedTun, mtu uint32) *tunLinkEndpoint {
	return &tunLinkEndpoint{tun: tun, mtu: mtu}
}

// Attach installs the dispatcher and starts the read loop the first time a
// non-nil dispatcher is attached. Attach(nil) on NIC removal just detaches;
// the loop keeps draining the fd (dropping packets) until it is closed, which
// matches the iobased behaviour.
func (e *tunLinkEndpoint) Attach(dispatcher stack.NetworkDispatcher) {
	e.mu.Lock()
	e.dispatcher = dispatcher
	e.mu.Unlock()
	if dispatcher == nil {
		return
	}
	e.startOnce.Do(func() {
		e.wg.Add(1)
		go func() {
			defer e.wg.Done()
			e.readLoop()
		}()
	})
}

func (e *tunLinkEndpoint) readLoop() {
	mtu := int(e.MTU())
	// One extra byte detects oversized packets, which are dropped like before.
	buf := make([]byte, mtu+1)
	for {
		n, err := e.tun.Read(buf)
		if err != nil {
			return
		}
		if n == 0 || n > mtu {
			continue
		}
		e.mu.RLock()
		d := e.dispatcher
		e.mu.RUnlock()
		if d == nil {
			continue
		}

		var proto tcpip.NetworkProtocolNumber
		switch header.IPVersion(buf[:n]) {
		case header.IPv4Version:
			proto = header.IPv4ProtocolNumber
		case header.IPv6Version:
			proto = header.IPv6ProtocolNumber
		default:
			continue
		}
		pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
			Payload: buffer.MakeWithData(buf[:n]),
		})
		d.DeliverNetworkPacket(proto, pkt)
		pkt.DecRef()
	}
}

// WritePackets copies each packet once into a pooled buffer and hands it to the
// asynchronous TUN writer. It never blocks; a full queue drops the packet, the
// same policy the previous channel endpoint plus bufferedTun applied.
func (e *tunLinkEndpoint) WritePackets(pkts stack.PacketBufferList) (int, tcpip.Error) {
	n := 0
	for _, pkt := range pkts.AsSlice() {
		e.tun.enqueuePacket(pkt)
		n++
	}
	return n, nil
}

func (e *tunLinkEndpoint) MTU() uint32 {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.mtu
}

func (e *tunLinkEndpoint) SetMTU(mtu uint32) {
	e.mu.Lock()
	e.mtu = mtu
	e.mu.Unlock()
}

func (e *tunLinkEndpoint) IsAttached() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.dispatcher != nil
}

func (e *tunLinkEndpoint) Wait()                                      { e.wg.Wait() }
func (*tunLinkEndpoint) MaxHeaderLength() uint16                      { return 0 }
func (*tunLinkEndpoint) LinkAddress() tcpip.LinkAddress               { return "" }
func (*tunLinkEndpoint) SetLinkAddress(tcpip.LinkAddress)             {}
func (*tunLinkEndpoint) Capabilities() stack.LinkEndpointCapabilities { return 0 }
func (*tunLinkEndpoint) ARPHardwareType() header.ARPHardwareType      { return header.ARPHardwareNone }
func (*tunLinkEndpoint) AddHeader(*stack.PacketBuffer)                {}
func (*tunLinkEndpoint) ParseHeader(*stack.PacketBuffer) bool         { return true }
func (*tunLinkEndpoint) Close()                                       {}
func (*tunLinkEndpoint) SetOnCloseAction(func())                      {}

var _ stack.LinkEndpoint = (*tunLinkEndpoint)(nil)

// enqueuePacket flattens pkt directly into a pooled buffer and queues it.
func (b *bufferedTun) enqueuePacket(pkt *stack.PacketBuffer) {
	size := pkt.Size()
	bufp := tunPacketPool.Get().(*[]byte)
	out := (*bufp)[:0]
	if cap(out) < size {
		out = make([]byte, 0, size)
	}
	views, offset := pkt.AsViewList()
	for v := views.Front(); v != nil && len(out) < size; v = v.Next() {
		data := v.AsSlice()
		if offset > 0 {
			if offset >= len(data) {
				offset -= len(data)
				continue
			}
			data = data[offset:]
			offset = 0
		}
		if remaining := size - len(out); len(data) > remaining {
			data = data[:remaining]
		}
		out = append(out, data...)
	}
	*bufp = out
	b.enqueue(bufp)
}
