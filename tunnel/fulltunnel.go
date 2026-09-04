package tunnel

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/miekg/dns"
	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

// bufferedTun lets the gVisor stack READ the TUN directly (inbound packets
// dispatched with no intermediate queue — this eliminates the inbound-pipe
// backpressure deadlock) while WRITES go to a background drain goroutine:
// direct-TUN mode writes outbound packets on the inbound-dispatch goroutine,
// and a blocking tunFile.Write (kernel buffer full under load) stalls dispatch
// and stops new flows. Write enqueues and drops on overflow (TCP retransmits).
type bufferedTun struct {
	tun  *os.File
	out  chan *[]byte
	stop chan struct{}
}

// tunWriteQueueDepth bounds buffered outbound packets. On overflow the
// packet is dropped (TCP retransmits), which is strictly better than
// blocking the gVisor dispatch goroutine.
const tunWriteQueueDepth = 2048

// tunPacketPool recycles outbound TUN packet buffers. Under load the
// gVisor stack emits thousands of packets per second; without pooling each
// Write heap-allocates (high alloc rate → short GC cycles → CPU spikes).
// Buffers hold one packet of at most the TUN MTU; anything larger falls
// back to plain allocation and is not returned to the pool.
const tunPooledMaxPacketBytes = 2 * defaultTunMTU

var tunPacketPool = sync.Pool{
	New: func() any {
		buf := make([]byte, 0, defaultTunMTU)
		return &buf
	},
}

func newBufferedTun(tun *os.File) *bufferedTun {
	b := &bufferedTun{tun: tun, out: make(chan *[]byte, tunWriteQueueDepth), stop: make(chan struct{})}
	go b.drain()
	return b
}

// Read passes through to the TUN so gVisor dispatches inbound packets
// directly (no queue).
func (b *bufferedTun) Read(p []byte) (int, error) { return b.tun.Read(p) }

// Write never blocks: copy + enqueue (pooled buffer), drop on overflow.
func (b *bufferedTun) Write(p []byte) (int, error) {
	bufp := tunPacketPool.Get().(*[]byte)
	pkt := append((*bufp)[:0], p...)
	*bufp = pkt // keep any grown capacity with the pooled entry
	select {
	case b.out <- bufp:
	default:
		// queue full — drop; TCP will retransmit.
		tunPacketPool.Put(bufp)
	}
	return len(p), nil
}

// drain writes queued packets to the real TUN until stopped or a write
// fails (TUN closed). Buffers are returned to the pool after each write.
func (b *bufferedTun) drain() {
	for {
		select {
		case bufp := <-b.out:
			_, err := b.tun.Write(*bufp)
			if cap(*bufp) <= tunPooledMaxPacketBytes {
				tunPacketPool.Put(bufp)
			}
			if err != nil {
				logf("StartFull: TUN drain write error, stopping writer: %v", err)
				return
			}
		case <-b.stop:
			return
		}
	}
}

// halt stops the drain goroutine. Safe to call once.
func (b *bufferedTun) halt() { close(b.stop) }

var _ io.ReadWriter = (*bufferedTun)(nil)

// fulltunnel.go — dedicated full-network HTTPS-filtering data path, separate
// from the legacy DnsInterceptor + bounded packetPipe path (which deadlocks
// under real browser load: the inbound queue fills, backpressure stalls every
// flow). This path hands the TUN fd DIRECTLY to the gVisor stack, exactly as
// tun2socks is designed to run:
//
//	 apps ─► TUN ─► gVisor stack (owns the fd; native flow control)
//	                 ├─ TCP any        → MITM handler (browser) / passthrough
//	                 ├─ UDP :53        → engine.ServeDNS (adblock + resolve)
//	                 ├─ UDP :443 (br)  → drop (force TCP so HTTP/3 can't dodge MITM)
//	                 └─ UDP other      → protected passthrough
//
// One dispatcher owns the TUN, reads AND writes it: no second reader, no pipe,
// no separate outbound-writer goroutine. The legacy Start() path is untouched;
// StartFull is only entered when the app selects full-network filtering.

// StartFull runs the engine in full-network capture mode. The gVisor
// stack reads the TUN fd directly and terminates every flow in userspace.
// StartStackMitm MUST have been called first to initialise the MITM CA +
// filter. Blocks until Stop() is called.
//
// gomobile usage (Kotlin), when full-network HTTPS filtering is on:
//
//	engine.setUseTcpStack(true)          // (informational; not used by StartFull)
//	engine.startStackMitm(certDir)       // CA + filter
//	engine.setMitmAllowedUIDs(uids)
//	engine.startFull(fd, protector)      // instead of engine.start(...)
func (e *Engine) StartFull(fd int, protector SocketProtector) {
	e.mu.Lock()
	if e.running {
		e.mu.Unlock()
		logf("StartFull: engine already running")
		return
	}
	e.running = true
	e.totalQueries.Store(0)
	e.blockedQueries.Store(0)
	// Fresh connection-log dedup set for this session.
	connLogSeen.Range(func(k, _ any) bool { connLogSeen.Delete(k); return true })

	var protectFn func(fd int) bool
	if protector != nil {
		protectFn = func(fd int) bool { return protector.Protect(fd) }
	}
	e.protectFn = protectFn
	e.flowOutbound = newFlowOutbound(e.outboundConfig, protectFn, e.reportOutboundStatus)
	if e.outboundConfig.Enabled {
		e.reportOutboundStatus("connecting", "")
	} else {
		e.reportOutboundStatus("disabled", "")
	}
	e.resolver = NewResolver(protectFn)
	e.resolver.SetRaceLogCallback(e.raceLogCallback)
	e.resolver.SetBootstrapLogCallback(e.bootstrapLogCallback)
	e.resolver.setOutbound(e.flowOutbound)
	if e.dnsConfig != nil {
		e.resolver.UpdateBootstrap(e.dnsConfig.Bootstrap)
		if err := e.resolver.ConfigureProviders(e.dnsConfig.Mode, e.dnsConfig.Providers); err != nil {
			logf("StartFull: DNS snapshot rejected: %v", err)
		}
	} else {
		e.resolver.Configure(ParseProtocol(e.protocol), e.primaryDNS, e.fallbackDNS, e.dohURL)
	}

	certMgr := e.stackCertMgr
	filter := e.stackMitmFilter
	uidr := e.uidResolver
	done := make(chan struct{})
	e.fullTunnelDone = done
	e.mu.Unlock()

	fail := func(format string, args ...interface{}) {
		logf(format, args...)
		e.mu.Lock()
		e.running = false
		e.fullTunnelDone = nil
		e.mu.Unlock()
	}

	// MITM is OPTIONAL. Full-tunnel mode captures all traffic regardless;
	// HTTPS MITM is a layer on top, active only when StartStackMitm has run
	// (HTTPS filtering enabled). Without it, full-tunnel still gives
	// all-app DNS filtering + per-app firewall + protected passthrough.
	mitmActive := certMgr != nil && filter != nil

	// Own the TUN fd (dup to avoid Android fdsan unique_fd crashes when the
	// ParcelFileDescriptor on the Kotlin side is closed).
	dupFd, err := syscall.Dup(fd)
	if err != nil {
		fail("StartFull: dup TUN fd %d failed: %v", fd, err)
		return
	}
	tunFile := os.NewFile(uintptr(dupFd), "tun")
	if tunFile == nil {
		fail("StartFull: open TUN fd %d failed", dupFd)
		return
	}

	stack := NewTcpIpStack()
	stack.SetUIDResolver(uidr)
	if mitmActive {
		// HTTPS filtering on → MITM browser TCP, adblock, cosmetic inject.
		stack.SetTcpHandler(newMitmTcpHandler(certMgr, filter, e, uidr, protectFn))
	} else {
		// Full-tunnel without HTTPS → protected passthrough (DNS-level filter).
		stack.SetTcpHandler(newFullPassthroughTcpHandler(e, uidr, protectFn))
	}
	stack.SetUdpHandler(newFullTunnelUdpHandler(e, filter, uidr, protectFn))
	logf("StartFull: mitm=%t", mitmActive)

	btun := newBufferedTun(tunFile)

	e.mu.Lock()
	e.tunFile = tunFile
	e.tcpStack = stack
	e.mu.Unlock()

	if err := stack.Start(btun, uint32(defaultTunMTU)); err != nil {
		btun.halt()
		tunFile.Close()
		e.mu.Lock()
		e.tcpStack = nil
		e.tunFile = nil
		e.mu.Unlock()
		fail("StartFull: stack start failed: %v", err)
		return
	}

	logf("StartFull: full-network stack running (direct TUN read, async TUN write, mtu=%d)", defaultTunMTU)

	e.trafficTracker.Start()
	if e.logAggregator != nil {
		e.logAggregator.start()
	}
	// Block until Stop() closes done.
	<-done
	if e.logAggregator != nil {
		e.logAggregator.stop()
	}
	e.trafficTracker.Stop()
	btun.halt()
	logf("StartFull: stopped")
}

// newFullTunnelUdpHandler routes UDP flows for full-network mode: DNS
// (port 53) is answered locally via engine.ServeDNS (the same adblock +
// resolve pipeline used in standalone/root mode); everything else falls
// through to the MITM-aware UDP handler (browser QUIC suppression +
// protected passthrough).
func newFullTunnelUdpHandler(engine *Engine, filter *MitmFilter, uidr UIDResolver, protectFn func(fd int) bool) UdpFlowHandler {
	return func(conn adapter.UDPConn) {
		defer conn.Close()
		flow := udpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolUDP, flow)
		if engine.isUIDBlocked(uid) {
			return
		}
		// DNS → answer locally (adblock + resolve).
		if flow.serverPort == 53 {
			handleDNSOverUDP(conn, engine, uid)
			return
		}
		if !engine.appAllowlistConnectionAllowed(uid, flow.serverIP) {
			return
		}
		engine.logConnection(flow, ProtocolUDP)
		// Browser QUIC (UDP 443): drop to force TCP TLS for MITM, only when
		// HTTP/3 filtering is enabled from the UI. Default off → relay QUIC
		// so pages load fully; DNS-level blocking applies either way.
		if engine.quicDrop.Load() && flow.serverPort == 443 && filter != nil && filter.HasAllowedUIDs() {
			if uid != UIDUnknown && filter.IsUIDAllowed(uid) {
				return
			}
		}
		outbound := engine.flowOutbound
		if outbound == nil {
			outbound = newFlowOutbound(outboundProxyConfig{}, protectFn, nil)
		}
		dst := net.JoinHostPort(flow.serverIP.String(), strconv.Itoa(flow.serverPort))
		ctx, cancel := context.WithTimeout(context.Background(), flowDialTimeout)
		remote, err := outbound.DialUDP(ctx, dst)
		cancel()
		if err != nil {
			logf("[FullTunnel] UDP uid=%d dial %s: %v", uid, dst, err)
			return
		}
		defer remote.Close()
		clientConn := engine.trafficTracker.WrapClientConn(conn, uid)
		relayUDPFlow(clientConn, remote)
	}
}

// newFullPassthroughTcpHandler is the full-tunnel TCP handler used when
// HTTPS MITM is OFF: every flow passes through a socket-protected dialer
// (private/loopback dialed directly so LAN stays reachable). DNS-level
// ad-blocking + firewall still apply via the DNS handler (ServeDNS).
//
// NOTE: firewall is not enforced per-connection here — calling the gomobile
// AppResolver JNI from this hot, highly-concurrent flow path panics under
// Go's cgocheck ("Go pointer to unpinned Go pointer"), so firewall
// enforcement stays at the DNS layer (a firewalled app can't resolve names).
func newFullPassthroughTcpHandler(engine *Engine, uidr UIDResolver, protectFn func(fd int) bool) TcpFlowHandler {
	return func(conn adapter.TCPConn) {
		defer conn.Close()
		flow := tcpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolTCP, flow)
		if engine.isUIDBlocked(uid) || !engine.appAllowlistConnectionAllowed(uid, flow.serverIP) {
			return
		}
		// DNS over TCP (port 53) → answer locally (adblock + resolve).
		if flow.serverPort == 53 {
			handleDNSOverTCP(conn, engine, uid)
			return
		}
		engine.logConnection(flow, ProtocolTCP)
		clientConn := engine.trafficTracker.WrapClientConn(conn, uid)
		relayDirectFromFlow(clientConn, flow, engine, protectFn)
	}
}

// SetFilterHttp3 toggles HTTP/3 (QUIC) filtering. When true, browser QUIC
// is dropped to force filterable TCP TLS (max in-page filtering, but some
// sites may load partially). When false (default), QUIC is relayed so
// pages load fully. Safe to call at any time; takes effect for new flows.
func (e *Engine) SetFilterHttp3(enabled bool) {
	e.quicDrop.Store(enabled)
	logf("SetFilterHttp3: HTTP/3 (QUIC) filtering = %t", enabled)
}

// SetBlockEncryptedDns controls whether selected HTTPS-filtered apps may use
// DNS-over-TLS. Non-selected and UID-unknown flows are always passed through.
func (e *Engine) SetBlockEncryptedDns(enabled bool) {
	e.blockEncryptedDNS.Store(enabled)
}

// SetBlockedUIDs replaces the Android UIDs whose traffic must be dropped.
// Unknown UIDs are always allowed so a resolver failure cannot block another app.
func (e *Engine) SetBlockedUIDs(uidsCsv string) {
	next := make(map[int]struct{})
	for _, raw := range strings.Split(uidsCsv, ",") {
		uid, err := strconv.Atoi(strings.TrimSpace(raw))
		if err == nil && uid > 0 {
			next[uid] = struct{}{}
		}
	}
	e.blockedUIDsMu.Lock()
	e.blockedUIDs = next
	e.blockedUIDsMu.Unlock()
}

func (e *Engine) isUIDBlocked(uid int) bool {
	if uid == UIDUnknown {
		return false
	}
	e.blockedUIDsMu.RLock()
	_, blocked := e.blockedUIDs[uid]
	e.blockedUIDsMu.RUnlock()
	return blocked
}

// dnsUDPIdleTimeout bounds how long a DNS UDP flow is kept open waiting
// for another query on the same 5-tuple before the handler goroutine
// exits. Most resolvers use a fresh source port per query (one query per
// flow), so this mainly reaps idle handlers promptly.
const dnsUDPIdleTimeout = 15 * time.Second

// handleDNSOverUDP reads DNS query datagrams off a stack UDP flow, runs
// each through engine.ServeDNS, and writes the packed response back to
// the app. Runs on its own goroutine per flow.
func handleDNSOverUDP(conn adapter.UDPConn, engine *Engine, uid int) {
	defer conn.Close()
	// Attribute DNS to the owning app (UID→package) so the log shows the
	// real app instead of "RootProxy". Resolved once per flow.
	appName := engine.appNameForFlow(udpFlowID(conn), ProtocolUDP)
	buf := make([]byte, 4096) // ample for a UDP DNS query (EDNS bufsize ≤ 4096)
	for {
		_ = conn.SetReadDeadline(time.Now().Add(dnsUDPIdleTimeout))
		n, err := conn.Read(buf)
		if err != nil {
			return
		}
		if engine.trafficTracker != nil && n > 0 {
			engine.trafficTracker.RecordTx(uid, int64(n))
		}
		req := new(dns.Msg)
		if err := req.Unpack(buf[:n]); err != nil {
			continue // not a parseable DNS message; ignore
		}
		engine.serveDNS(&udpDNSResponseWriter{conn: conn, engine: engine, uid: uid}, req, appName, uid)
	}
}

// udpDNSResponseWriter adapts a stack UDP flow to dns.ResponseWriter so
// engine.ServeDNS can reply on it. Only the methods ServeDNS actually
// uses (WriteMsg, RemoteAddr) do real work; the rest are minimal
// conformance stubs.
type udpDNSResponseWriter struct {
	conn   adapter.UDPConn
	engine *Engine
	uid    int
}

func (w *udpDNSResponseWriter) LocalAddr() net.Addr  { return w.conn.LocalAddr() }
func (w *udpDNSResponseWriter) RemoteAddr() net.Addr { return w.conn.RemoteAddr() }

func (w *udpDNSResponseWriter) WriteMsg(m *dns.Msg) error {
	packed, err := m.Pack()
	if err != nil {
		return err
	}
	if w.engine != nil && w.engine.trafficTracker != nil && len(packed) > 0 {
		w.engine.trafficTracker.RecordRx(w.uid, int64(len(packed)))
	}
	_, err = w.conn.Write(packed)
	return err
}

func (w *udpDNSResponseWriter) Write(b []byte) (int, error) {
	if w.engine != nil && w.engine.trafficTracker != nil && len(b) > 0 {
		w.engine.trafficTracker.RecordRx(w.uid, int64(len(b)))
	}
	return w.conn.Write(b)
}

// Close is a no-op: the owning handleDNSOverUDP loop owns the conn and
// closes it when the flow ends.
func (w *udpDNSResponseWriter) Close() error   { return nil }
func (w *udpDNSResponseWriter) TsigStatus() error { return nil }
func (w *udpDNSResponseWriter) TsigTimersOnly(bool) {}
func (w *udpDNSResponseWriter) Hijack()             {}

const dnsTCPIdleTimeout = 15 * time.Second

// handleDNSOverTCP reads DNS query messages with 2-byte prefix off a stack TCP flow,
// runs each through engine.serveDNS, and writes the 2-byte prefixed response back to
// the app.
func handleDNSOverTCP(conn adapter.TCPConn, engine *Engine, uid int) {
	defer conn.Close()
	appName := engine.appNameForFlow(tcpFlowID(conn), ProtocolTCP)
	lenBuf := make([]byte, 2)
	for {
		_ = conn.SetReadDeadline(time.Now().Add(dnsTCPIdleTimeout))
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			return
		}
		msgLen := binary.BigEndian.Uint16(lenBuf)
		if msgLen == 0 {
			continue
		}
		buf := make([]byte, msgLen)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		if engine.trafficTracker != nil {
			engine.trafficTracker.RecordTx(uid, int64(2+int(msgLen)))
		}
		req := new(dns.Msg)
		if err := req.Unpack(buf); err != nil {
			continue
		}
		engine.serveDNS(&tcpDNSResponseWriter{conn: conn, engine: engine, uid: uid}, req, appName, uid)
	}
}

// tcpDNSResponseWriter adapts a stack TCP flow to dns.ResponseWriter.
type tcpDNSResponseWriter struct {
	conn   adapter.TCPConn
	engine *Engine
	uid    int
}

func (w *tcpDNSResponseWriter) LocalAddr() net.Addr  { return w.conn.LocalAddr() }
func (w *tcpDNSResponseWriter) RemoteAddr() net.Addr { return w.conn.RemoteAddr() }

func (w *tcpDNSResponseWriter) WriteMsg(m *dns.Msg) error {
	packed, err := m.Pack()
	if err != nil {
		return err
	}
	return w.writeBytes(packed)
}

func (w *tcpDNSResponseWriter) Write(b []byte) (int, error) {
	err := w.writeBytes(b)
	if err != nil {
		return 0, err
	}
	return len(b), nil
}

func (w *tcpDNSResponseWriter) writeBytes(b []byte) error {
	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(b)))
	total := append(lenBuf, b...)
	if w.engine != nil && w.engine.trafficTracker != nil && len(total) > 0 {
		w.engine.trafficTracker.RecordRx(w.uid, int64(len(total)))
	}
	_ = w.conn.SetWriteDeadline(time.Now().Add(dnsTCPIdleTimeout))
	_, err := w.conn.Write(total)
	return err
}

func (w *tcpDNSResponseWriter) Close() error        { return nil }
func (w *tcpDNSResponseWriter) TsigStatus() error    { return nil }
func (w *tcpDNSResponseWriter) TsigTimersOnly(bool)  {}
func (w *tcpDNSResponseWriter) Hijack()              {}

