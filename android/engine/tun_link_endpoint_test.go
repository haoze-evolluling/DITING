package tunnel

import (
	"bytes"
	"io"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/header"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

type recordingWriter struct {
	mu   sync.Mutex
	pkts [][]byte
}

func (w *recordingWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	w.pkts = append(w.pkts, append([]byte(nil), p...))
	w.mu.Unlock()
	return len(p), nil
}

func (w *recordingWriter) get() [][]byte {
	w.mu.Lock()
	defer w.mu.Unlock()
	return append([][]byte(nil), w.pkts...)
}

// Outbound packets with prepended headers must be flattened in header+payload
// order, exactly as PacketBuffer.ToBuffer().Flatten() would produce.
func TestTunLinkEndpointWritesFlattenedPacket(t *testing.T) {
	w := &recordingWriter{}
	b := newBufferedTunWithWriter(nil, w)
	defer b.halt()
	ep := newTunLinkEndpoint(b, defaultTunMTU)

	payload := bytes.Repeat([]byte{0xAB}, 900)
	pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
		ReserveHeaderBytes: 40,
		Payload:            buffer.MakeWithData(payload),
	})
	hdr := pkt.TransportHeader().Push(20)
	for i := range hdr {
		hdr[i] = byte(i)
	}
	want := pkt.ToBuffer()
	wantBytes := want.Flatten()
	want.Release()

	var list stack.PacketBufferList
	list.PushBack(pkt)
	if n, err := ep.WritePackets(list); n != 1 || err != nil {
		t.Fatalf("WritePackets = %d, %v", n, err)
	}
	pkt.DecRef()

	if !waitFor(t, 2*time.Second, func() bool { return len(w.get()) == 1 }) {
		t.Fatal("packet not written to TUN")
	}
	if got := w.get()[0]; !bytes.Equal(got, wantBytes) {
		t.Fatalf("written %d bytes, want %d (equal=%t)", len(got), len(wantBytes), bytes.Equal(got, wantBytes))
	}
}

type captureDispatcher struct {
	mu    sync.Mutex
	got   [][]byte
	proto []tcpip.NetworkProtocolNumber
}

func (d *captureDispatcher) DeliverNetworkPacket(p tcpip.NetworkProtocolNumber, pkt *stack.PacketBuffer) {
	b := pkt.ToBuffer()
	d.mu.Lock()
	d.got = append(d.got, b.Flatten())
	d.proto = append(d.proto, p)
	d.mu.Unlock()
	b.Release()
}

func (d *captureDispatcher) DeliverLinkPacket(tcpip.NetworkProtocolNumber, *stack.PacketBuffer) {}

func (d *captureDispatcher) count() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.got)
}

// Inbound reads reuse one buffer, so each delivered packet must still carry its
// own bytes; oversized and non-IP packets are dropped.
func TestTunLinkEndpointReadLoopDeliversIndependentPackets(t *testing.T) {
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	b := newBufferedTunWithWriter(r, io.Discard)
	defer b.halt()
	ep := newTunLinkEndpoint(b, defaultTunMTU)
	d := &captureDispatcher{}
	ep.Attach(d)

	v4 := append([]byte{0x45}, bytes.Repeat([]byte{1}, 99)...)
	v6 := append([]byte{0x60}, bytes.Repeat([]byte{2}, 199)...)
	// A pipe is a byte stream, so write and wait one packet at a time to keep
	// read boundaries aligned with packets as a TUN fd would.
	for i, p := range [][]byte{v4, {0x10, 0, 0}, v6} {
		if _, err := w.Write(p); err != nil {
			t.Fatal(err)
		}
		want := []int{1, 1, 2}[i]
		if !waitFor(t, 2*time.Second, func() bool { return d.count() == want }) && i != 1 {
			t.Fatalf("after packet %d delivered %d", i, d.count())
		}
		time.Sleep(20 * time.Millisecond)
	}
	w.Close()
	ep.Wait()
	r.Close()

	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.got) != 2 || !bytes.Equal(d.got[0], v4) || !bytes.Equal(d.got[1], v6) {
		t.Fatalf("delivered %d packets, v4 ok=%t", len(d.got), len(d.got) > 0 && bytes.Equal(d.got[0], v4))
	}
	if d.proto[0] != 0x0800 || d.proto[1] != 0x86dd {
		t.Fatalf("protocols = %v", d.proto)
	}
}

// End-to-end through the real gVisor stack: SYN in -> SYN-ACK out on the TUN
// write side -> final ACK in -> TCP handler invoked (gVisor's forwarder only
// calls the handler after the three-way handshake completes).
func TestTunLinkEndpointStackHandshake(t *testing.T) {
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	out := &recordingWriter{}
	b := newBufferedTunWithWriter(r, out)
	defer b.halt()

	handled := make(chan struct{}, 1)
	st := NewTcpIpStack()
	st.SetTcpHandler(func(conn adapter.TCPConn) {
		handled <- struct{}{}
		conn.Close()
	})
	if err := st.StartWithEndpoint(newTunLinkEndpoint(b, defaultTunMTU), defaultTunMTU); err != nil {
		t.Fatal(err)
	}
	defer st.Stop()
	defer w.Close()

	src := tcpip.AddrFrom4([4]byte{10, 0, 0, 2})
	dst := tcpip.AddrFrom4([4]byte{93, 184, 216, 34})
	if _, err := w.Write(buildTCPv4(src, dst, 1000, 0, header.TCPFlagSyn)); err != nil {
		t.Fatal(err)
	}

	var synAck header.TCP
	if !waitFor(t, 3*time.Second, func() bool {
		for _, p := range out.get() {
			ip := header.IPv4(p)
			if len(p) < header.IPv4MinimumSize+header.TCPMinimumSize {
				continue
			}
			seg := header.TCP(p[ip.HeaderLength():])
			if seg.Flags().Contains(header.TCPFlagSyn|header.TCPFlagAck) && ip.SourceAddress() == dst {
				synAck = seg
				return true
			}
		}
		return false
	}) {
		t.Fatalf("no SYN-ACK written to TUN (%d packets)", len(out.get()))
	}
	if synAck.AckNumber() != 1001 {
		t.Fatalf("SYN-ACK ack=%d, want 1001", synAck.AckNumber())
	}

	if _, err := w.Write(buildTCPv4(src, dst, 1001, synAck.SequenceNumber()+1, header.TCPFlagAck)); err != nil {
		t.Fatal(err)
	}
	select {
	case <-handled:
	case <-time.After(3 * time.Second):
		t.Fatal("TCP handler never invoked after handshake")
	}
}

func buildTCPv4(src, dst tcpip.Address, seq, ack uint32, flags header.TCPFlags) []byte {
	pkt := make([]byte, header.IPv4MinimumSize+header.TCPMinimumSize)
	ip := header.IPv4(pkt)
	ip.Encode(&header.IPv4Fields{
		TotalLength: uint16(len(pkt)), TTL: 64, Protocol: uint8(header.TCPProtocolNumber),
		SrcAddr: src, DstAddr: dst,
	})
	ip.SetChecksum(^ip.CalculateChecksum())
	tcp := header.TCP(pkt[header.IPv4MinimumSize:])
	tcp.Encode(&header.TCPFields{
		SrcPort: 40000, DstPort: 443, SeqNum: seq, AckNum: ack,
		DataOffset: header.TCPMinimumSize, Flags: flags, WindowSize: 65535,
	})
	xsum := header.PseudoHeaderChecksum(header.TCPProtocolNumber, src, dst, uint16(len(tcp)))
	tcp.SetChecksum(^tcp.CalculateChecksum(xsum))
	return pkt
}
