// tcp_ip_stack.go wraps the gVisor userspace TCP/IP stack via tun2socks, terminating L4 network flows.
//
// Concurrency & Dispatching:
// - 5-Tuple Visibility: Inspects real local/remote socket endpoints to enable per-app UID attribution.
// - Goroutine Decoupling: UDP handlers are dispatched on dedicated goroutines to prevent stalling tun2socks's
//   synchronous single-threaded UDP dispatch loop during blocking operations or relay loops.

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

type TcpFlowHandler func(conn adapter.TCPConn)

type UdpFlowHandler func(conn adapter.UDPConn)

type TcpIpStack struct {
	mu       sync.Mutex
	stack    *gvisorStack.Stack
	endpoint *iobased.Endpoint
	running  atomic.Bool

	tcpHandler TcpFlowHandler
	udpHandler UdpFlowHandler
	uidr       UIDResolver

	tcpFlows atomic.Int64
	udpFlows atomic.Int64
}

func NewTcpIpStack() *TcpIpStack {
	return &TcpIpStack{}
}

func (s *TcpIpStack) SetTcpHandler(h TcpFlowHandler) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tcpHandler = h
}

func (s *TcpIpStack) SetUdpHandler(h UdpFlowHandler) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.udpHandler = h
}

func (s *TcpIpStack) SetUIDResolver(r UIDResolver) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.uidr = r
}

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

func (s *TcpIpStack) IsRunning() bool { return s.running.Load() }

func (s *TcpIpStack) TcpFlowCount() int64 { return s.tcpFlows.Load() }

func (s *TcpIpStack) UdpFlowCount() int64 { return s.udpFlows.Load() }

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

		logf("TcpIpStack: TCP uid=%d %s:%d → %s:%d (no handler, dropping)",
			uid, flow.appIP, flow.appPort, flow.serverIP, flow.serverPort)
		_ = conn.Close()
		return
	}
	h(conn)
}

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

	go h(conn)
}

var _ adapter.TransportHandler = (*TcpIpStack)(nil)
