// traffic_tracker_test.go pins the traffic wrapper's capability preservation.
//
// WrapClientConn wraps the client-side flow conn to account bytes per UID. The
// wrapper embeds the net.Conn *interface*, so TCP half-close (CloseWrite) does
// not promote through it. The relay helpers (bidiCopyFlow, relayDirectPeeked)
// assert CloseWrite on exactly that wrapped conn, so the assertion silently
// failed and the FIN was never sent: TLS clients that shut down their write side
// after a request waited for a response the upstream never produced.
//
// The wrapper must therefore re-advertise CloseWrite when, and only when, the
// wrapped transport supports it.

package tunnel

import (
	"errors"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"
)

// halfCloseConn is a net.Conn that supports TCP half-close, like gVisor's
// gonet.TCPConn (which sits behind adapter.TCPConn in the MITM path).
type halfCloseConn struct {
	net.Conn
	closeWrites  atomic.Int32
	closeWriteEr error
}

func (c *halfCloseConn) CloseWrite() error {
	c.closeWrites.Add(1)
	return c.closeWriteEr
}

// plainConn is a net.Conn without half-close support (UDP-like transports).
type plainConn struct {
	net.Conn
}

func newPipePair(t *testing.T) (net.Conn, net.Conn) {
	t.Helper()
	a, b := net.Pipe()
	t.Cleanup(func() {
		_ = a.Close()
		_ = b.Close()
	})
	return a, b
}

// The core regression: the assertion the relay helpers perform must succeed on
// the value WrapClientConn returns, and it must reach the real transport.
func TestWrapClientConnPreservesCloseWrite(t *testing.T) {
	transport, peer := newPipePair(t)
	half := &halfCloseConn{Conn: transport}
	tracker := newTrafficTracker()

	wrapped := tracker.WrapClientConn(half, 10123)
	if wrapped == half {
		t.Fatal("WrapClientConn must wrap a valid uid")
	}

	cw, ok := wrapped.(interface{ CloseWrite() error })
	if !ok {
		t.Fatal("wrapper dropped CloseWrite; relay helpers cannot half-close the client conn")
	}
	if err := cw.CloseWrite(); err != nil {
		t.Fatalf("CloseWrite must forward without error: %v", err)
	}
	if got := half.closeWrites.Load(); got != 1 {
		t.Fatalf("CloseWrite did not reach the transport (calls=%d)", got)
	}

	// Byte accounting must still work through the half-close wrapper.
	go func() { _, _ = peer.Write([]byte("hello")) }()
	buf := make([]byte, 5)
	_ = transport.SetReadDeadline(time.Now().Add(2 * time.Second))
	if n, err := wrapped.Read(buf); err != nil || n != 5 {
		t.Fatalf("wrapped Read: n=%d err=%v", n, err)
	}
	go func() { _, _ = io.Copy(io.Discard, peer) }()
	_ = transport.SetWriteDeadline(time.Now().Add(2 * time.Second))
	if _, err := wrapped.Write([]byte("reply")); err != nil {
		t.Fatalf("wrapped Write: %v", err)
	}

	// Byte accounting must still work through the half-close wrapper:
	// Read from the client counts as Tx, Write towards it as Rx.
	counters := tracker.getOrCreateCounters(10123)
	if got := counters.txTotal.Load(); got != 5 {
		t.Fatalf("wrapped Read was not accounted as Tx (tx=%d)", got)
	}
	if got := counters.rxTotal.Load(); got != 5 {
		t.Fatalf("wrapped Write was not accounted as Rx (rx=%d)", got)
	}
}

// A transport without half-close must not be given a fake CloseWrite: the relay
// helpers would then take a branch that does nothing meaningful for UDP-style
// conns, hiding real transport errors.
func TestWrapClientConnDoesNotInventCloseWrite(t *testing.T) {
	transport, _ := newPipePair(t)
	plain := &plainConn{Conn: transport}

	wrapped := newTrafficTracker().WrapClientConn(plain, 10124)
	if _, ok := wrapped.(interface{ CloseWrite() error }); ok {
		t.Fatal("wrapper advertised CloseWrite for a transport that does not support it")
	}
	if _, ok := wrapped.(interface{ Read([]byte) (int, error) }); !ok {
		t.Fatal("wrapper must still be a usable net.Conn")
	}
}

// Forwarding must propagate the transport's error, not swallow it.
func TestWrapClientConnForwardsCloseWriteError(t *testing.T) {
	transport, _ := newPipePair(t)
	half := &halfCloseConn{Conn: transport, closeWriteEr: errors.New("already closed")}

	cw, ok := newTrafficTracker().WrapClientConn(half, 10125).(interface{ CloseWrite() error })
	if !ok {
		t.Fatal("CloseWrite not promoted")
	}
	if err := cw.CloseWrite(); err == nil {
		t.Fatal("transport error must be surfaced")
	}
}

// uid <= 0 means "not attributable to an app"; the original conn is returned
// unchanged, so half-close keeps working through the plain transport.
func TestWrapClientConnPassesThroughUnattributedFlows(t *testing.T) {
	transport, _ := newPipePair(t)
	half := &halfCloseConn{Conn: transport}
	tracker := newTrafficTracker()

	for _, uid := range []int{0, -1, UIDUnknown} {
		if got := tracker.WrapClientConn(half, uid); got != net.Conn(half) {
			t.Fatalf("uid=%d must pass the conn through unchanged", uid)
		}
	}
	if got := (*TrafficTracker)(nil).WrapClientConn(half, 10123); got != net.Conn(half) {
		t.Fatal("nil tracker must pass the conn through unchanged")
	}
}
