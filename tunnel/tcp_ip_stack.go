package tunnel

import (
	"fmt"
	"io"
	"sync"
	"sync/atomic"

	"github.com/xjasonlyu/tun2socks/v2/core"
	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
	"github.com/xjasonlyu/tun2socks/v2/core/device/iobased"
	"github.com/xjasonlyu/tun2socks/v2/core/option"
	gvisorStack "gvisor.dev/gvisor/pkg/tcpip/stack"
)

// TcpIpStack — userspace TCP/IP stack backed by gVisor via tun2socks. It
// terminates every TCP/UDP flow entering the TUN device in userspace and
// hands each connection to the registered flow handler. Unlike the system
// HTTP proxy approach, this model sees the real 5-tuple
// (src IP:port → dst IP:port) on every connection, letting us look up the
// owning app UID via Android's ConnectivityManager.getConnectionOwnerUid()
// — the visibility that enables per-app scoping of HTTPS filtering.

// TcpFlowHandler is invoked on its own goroutine for every TCP connection
// terminated by the stack and owns the connection for its full lifetime
// (read/write as needed, then Close); the stack never dispatches the same
// conn twice. conn.ID() carries the 5-tuple: LocalAddress/LocalPort are the
// original TUN destination (the real remote server the app was reaching),
// RemoteAddress/RemotePort the app's ephemeral socket; Write sends bytes back
// to the app, Read consumes bytes from the app.
type TcpFlowHandler func(conn adapter.TCPConn)

// UdpFlowHandler is invoked on its own goroutine for every UDP flow.
// Same ownership semantics as TcpFlowHandler — the handler runs for
// the flow's lifetime and must Close() when finished.
type UdpFlowHandler func(conn adapter.UDPConn)

// TcpIpStack wraps the gVisor-backed userspace TCP/IP stack provided by
// tun2socks. A single instance manages one TUN file descriptor and
// dispatches every terminated flow to the registered handlers.
type TcpIpStack struct {
	mu       sync.Mutex
	stack    *gvisorStack.Stack
	endpoint *iobased.Endpoint
	running  atomic.Bool

	tcpHandler TcpFlowHandler
	udpHandler UdpFlowHandler
	uidr       UIDResolver

	// stats
	tcpFlows atomic.Int64
	udpFlows atomic.Int64
}

// NewTcpIpStack creates an unconfigured stack. Call Start to begin
// processing packets from a TUN file descriptor.
func NewTcpIpStack() *TcpIpStack {
	return &TcpIpStack{}
}

// SetTcpHandler registers the handler invoked for each new TCP connection.
// Must be called before Start. If nil, TCP connections are immediately
// closed.
func (s *TcpIpStack) SetTcpHandler(h TcpFlowHandler) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tcpHandler = h
}

// SetUdpHandler registers the handler invoked for each new UDP flow.
// Must be called before Start. If nil, UDP flows are immediately closed.
func (s *TcpIpStack) SetUdpHandler(h UdpFlowHandler) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.udpHandler = h
}

// SetUIDResolver registers the resolver used to look up the owning app
// UID for each flow. May be nil (falls back to UIDUnknown for every
// flow). Typically wired from Kotlin via Engine.SetUIDResolver.
func (s *TcpIpStack) SetUIDResolver(r UIDResolver) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.uidr = r
}

// Start constructs the gVisor stack on top of the supplied ReadWriter and
// begins processing packets. Read must return one IP packet per call (up to
// mtu bytes); Write receives one IP packet per call. Start does not take
// ownership of the ReadWriter — Stop tears down the stack only; closing the
// underlying fd or pipe is the caller's responsibility.
func (s *TcpIpStack) Start(rw io.ReadWriter, mtu uint32) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.running.Load() {
		return fmt.Errorf("tcp/ip stack already running")
	}

	ep, err := iobased.New(rw, mtu, 0)
	if err != nil {
		return fmt.Errorf("create iobased endpoint: %w", err)
	}

	st, err := core.CreateStack(&core.Config{
		LinkEndpoint:     ep,
		TransportHandler: s,
		Options:          []option.Option{},
	})
	if err != nil {
		return fmt.Errorf("create stack: %w", err)
	}

	s.endpoint = ep
	s.stack = st
	s.running.Store(true)

	logf("TcpIpStack: started (mtu=%d)", mtu)
	return nil
}

// Stop tears down the stack. Safe to call multiple times.
//
// Known issue: gVisor dispatch goroutines may still read from the device
// when stack.Close() races with device.Close(); tun2socks' own examples
// close the LinkEndpoint first, then drain, then close the stack.
func (s *TcpIpStack) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.running.Load() {
		return
	}
	s.running.Store(false)

	if s.stack != nil {
		s.stack.Close()
		s.stack = nil
	}
	s.endpoint = nil
	logf("TcpIpStack: stopped (tcp=%d udp=%d flows handled)", s.tcpFlows.Load(), s.udpFlows.Load())
}

// IsRunning reports whether the stack is currently processing packets.
func (s *TcpIpStack) IsRunning() bool { return s.running.Load() }

// TcpFlowCount returns the total number of TCP flows dispatched.
func (s *TcpIpStack) TcpFlowCount() int64 { return s.tcpFlows.Load() }

// UdpFlowCount returns the total number of UDP flows dispatched.
func (s *TcpIpStack) UdpFlowCount() int64 { return s.udpFlows.Load() }

// HandleTCP implements adapter.TransportHandler. Invoked by gVisor for
// every terminated TCP connection.
func (s *TcpIpStack) HandleTCP(conn adapter.TCPConn) {
	c := s.tcpFlows.Add(1)

	s.mu.Lock()
	h := s.tcpHandler
	uidr := s.uidr
	s.mu.Unlock()

	flow := tcpFlowID(conn)
	uid := resolveFlowUID(uidr, ProtocolTCP, flow)

	if c <= 5 {
		logf("TcpIpStack: HandleTCP #%d uid=%d %s:%d → %s:%d (handler set: %t)",
			c, uid, flow.appIP, flow.appPort, flow.serverIP, flow.serverPort, h != nil)
	}

	if h == nil {
		// Default path: log the 5-tuple + UID, drop the connection.
		logf("TcpIpStack: TCP uid=%d %s:%d → %s:%d (no handler, dropping)",
			uid, flow.appIP, flow.appPort, flow.serverIP, flow.serverPort)
		_ = conn.Close()
		return
	}
	h(conn)
}

// HandleUDP implements adapter.TransportHandler. Invoked for every UDP flow.
func (s *TcpIpStack) HandleUDP(conn adapter.UDPConn) {
	s.udpFlows.Add(1)

	s.mu.Lock()
	h := s.udpHandler
	uidr := s.uidr
	s.mu.Unlock()

	flow := udpFlowID(conn)
	uid := resolveFlowUID(uidr, ProtocolUDP, flow)

	if h == nil {
		logf("TcpIpStack: UDP uid=%d %s:%d → %s:%d (no handler, dropping)",
			uid, flow.appIP, flow.appPort, flow.serverIP, flow.serverPort)
		_ = conn.Close()
		return
	}
	// CRITICAL: run the UDP handler on its own goroutine. tun2socks invokes
	// this callback SYNCHRONOUSLY on the stack's single dispatch goroutine
	// (unlike TCP, which dispatches on a fresh goroutine), so a blocking
	// handler — the DNS read loop, a UDP relay's bidiCopy — would stall ALL
	// traffic (observed: dispatch loop parked in handleDNSOverUDP→conn.Read).
	// The conn stays valid after the callback returns.
	go h(conn)
}

// Compile-time assertion that TcpIpStack implements the tun2socks
// transport handler interface.
var _ adapter.TransportHandler = (*TcpIpStack)(nil)
