// engine_full_tunnel.go implements the high-throughput full-network data plane for HTTPS filtering.
//
// Architecture & Deadlock Elimination:
// - Direct TUN Inbound: gVisor reads the TUN device directly to eliminate intermediate packet queue backpressure deadlocks.
// - Non-Blocking Outbound: bufferedTun decouples writes into an outbound channel with a sync.Pool buffer pool (tunPacketPool),
//   dropping on overflow to prioritize dispatch loop responsiveness.
// - Self-Healing Outbound Writer: a TUN write error is treated as transient. The drain goroutine retries with backoff
//   instead of exiting, so a network handover cannot blackhole the outbound direction for the rest of the session.
// - Flow Routing Topology:
//     apps -> TUN -> gVisor stack:
//       • TCP: Routed to MITM handler or direct protected passthrough.
//       • UDP :53: Handled by Engine.ServeDNS for ad blocking and resolution.
//       • UDP :443: Dropped for targeted browsers to force HTTP/3 fallback to TCP TLS for inspection.
//       • UDP other: Relayed via protected sockets.

package tunnel

import (
	"context"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

type bufferedTun struct {
	tun    *os.File  // TUN device; Read side, and the default Write side
	writer io.Writer // Write side; overridable in tests
	out    chan *[]byte
	stop   chan struct{}

	stopOnce sync.Once

	// healthy is false after a write exhausted its retry budget and true again
	// once any write succeeds, so a persistently failing interface is probed
	// with single attempts instead of paying the full backoff per packet.
	healthy atomic.Bool

	dropped       atomic.Int64
	writeFailures atomic.Int64
}

const tunWriteQueueDepth = 2048

const tunPooledMaxPacketBytes = 2 * defaultTunMTU

// A network handover (Wi-Fi <-> cellular, interface flap) surfaces as ENETDOWN /
// EINVAL / EBUSY on the TUN fd for a short window; the writer must ride it out.
const (
	tunWriteRetryAttempts = 40
	tunWriteRetryBaseWait = 5 * time.Millisecond
	tunWriteRetryMaxWait  = 100 * time.Millisecond
)

var tunPacketPool = sync.Pool{
	New: func() any {
		buf := make([]byte, 0, defaultTunMTU)
		return &buf
	},
}

func newBufferedTun(tun *os.File) *bufferedTun {
	return newBufferedTunWithWriter(tun, tun)
}

// newBufferedTunWithWriter lets tests inject a failing writer; production always
// passes the TUN file for both directions.
func newBufferedTunWithWriter(tun *os.File, writer io.Writer) *bufferedTun {
	b := &bufferedTun{
		tun:    tun,
		writer: writer,
		out:    make(chan *[]byte, tunWriteQueueDepth),
		stop:   make(chan struct{}),
	}
	b.healthy.Store(true)
	go b.drain()
	return b
}

func (b *bufferedTun) Read(p []byte) (int, error) { return b.tun.Read(p) }

// Write never reports an error: the link endpoint has no use for the returned
// error and does not retry, so surfacing one would only lose the packet anyway.
// Dropping on a full queue is the same policy, and TCP retransmits.
func (b *bufferedTun) Write(p []byte) (int, error) {
	bufp := tunPacketPool.Get().(*[]byte)
	pkt := append((*bufp)[:0], p...)
	*bufp = pkt
	b.enqueue(bufp)
	return len(p), nil
}

// enqueue hands a pooled packet to the drain goroutine, dropping on overflow.
func (b *bufferedTun) enqueue(bufp *[]byte) {
	select {
	case b.out <- bufp:
	default:
		tunPacketPool.Put(bufp)
		if n := b.dropped.Add(1); n <= 3 || n%1024 == 0 {
			logf("StartFull: outbound queue full, dropped %d packet(s)", n)
		}
	}
}

// drain moves packets from the queue to the TUN device for the whole session.
//
// A write error used to end this goroutine permanently while Write kept
// reporting success, so every later outbound packet was silently discarded and
// only restarting the VPN session restored connectivity. Errors are now retried
// with backoff, and a write that still fails is dropped while the writer stays
// alive, so the tunnel recovers by itself as soon as the interface does.
func (b *bufferedTun) drain() {
	for {
		select {
		case bufp := <-b.out:
			pkt := *bufp
			alive := b.writeWithRetry(pkt)
			if cap(*bufp) <= tunPooledMaxPacketBytes {
				tunPacketPool.Put(bufp)
			}
			if !alive {
				return
			}
		case <-b.stop:
			return
		}
	}
}

// writeWithRetry writes one packet, returning false only when the writer was
// halted. A dropped packet after the retry budget keeps the goroutine running.
func (b *bufferedTun) writeWithRetry(pkt []byte) bool {
	attempts := 1
	if b.healthy.Load() {
		attempts = tunWriteRetryAttempts
	}
	wait := tunWriteRetryBaseWait

	for attempt := 1; ; attempt++ {
		_, err := b.writer.Write(pkt)
		if err == nil {
			if !b.healthy.Swap(true) {
				logf("StartFull: TUN writes recovered")
			}
			return true
		}
		if attempt >= attempts {
			b.healthy.Store(false)
			n := b.writeFailures.Add(1)
			if n <= 5 || n%100 == 0 {
				logf("StartFull: TUN write failed (%d dropped), keeping writer alive: %v", n, err)
			}
			return true
		}
		timer := time.NewTimer(wait)
		select {
		case <-timer.C:
		case <-b.stop:
			timer.Stop()
			return false
		}
		if wait < tunWriteRetryMaxWait {
			wait *= 2
			if wait > tunWriteRetryMaxWait {
				wait = tunWriteRetryMaxWait
			}
		}
	}
}

func (b *bufferedTun) halt() { b.stopOnce.Do(func() { close(b.stop) }) }

var _ io.ReadWriter = (*bufferedTun)(nil)

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

	connLogSeen.reset()

	var protectFn func(fd int) bool
	if protector != nil {
		protectFn = func(fd int) bool { return protector.Protect(fd) }
	}
	e.protectFn = protectFn
	e.flowOutbound = newFlowOutbound(e.outboundConfig, protectFn, e.reportOutboundStatus)
	route := newOutboundRoute(e.outboundConfig, e.flowOutbound, protectFn)
	e.outboundRouteView.Store(route)
	if e.outboundConfig.Enabled {
		e.reportOutboundStatus("connecting", "")
	} else {
		e.reportOutboundStatus("disabled", "")
	}
	e.setResolverLocked(NewResolver(protectFn))
	e.resolver.SetRaceLogCallback(e.raceLogCallback)
	e.resolver.SetBootstrapLogCallback(e.bootstrapLogCallback)
	e.resolver.setOutbound(route.resolverOutbound())
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
	// Pin the session this call belongs to. Everything published after the unlock
	// below is conditional on the generation still matching, so a Stop() (or a
	// Stop()+StartFull() pair) that lands during the expensive setup cannot be
	// clobbered by this stale call. Comparing `done` alone would not catch a
	// second StartFull reusing the same channel identity across sessions.
	gen := e.sessionGen
	e.mu.Unlock()

	// stillCurrent reports whether this call is still the session that owns the
	// engine. Callers hold mu.
	stillCurrent := func() bool { return e.running && e.sessionGen == gen }

	fail := func(format string, args ...interface{}) {
		logf(format, args...)
		e.mu.Lock()
		if stillCurrent() {
			e.running = false
			e.fullTunnelDone = nil
		}
		e.mu.Unlock()
	}

	mitmActive := certMgr != nil && filter != nil

	newFd, err := dupFd(fd)
	if err != nil {
		fail("StartFull: dup TUN fd %d failed: %v", fd, err)
		return
	}
	tunFile := os.NewFile(uintptr(newFd), "tun")
	if tunFile == nil {
		fail("StartFull: open TUN fd %d failed", dupFd)
		return
	}

	stack := NewTcpIpStack()
	stack.SetUIDResolver(uidr)
	if mitmActive {

		stack.SetTcpHandler(newMitmTcpHandler(certMgr, filter, e, uidr, protectFn))
	} else {

		stack.SetTcpHandler(newFullPassthroughTcpHandler(e, uidr, protectFn))
	}
	stack.SetUdpHandler(newFullTunnelUdpHandler(e, filter, uidr, protectFn))
	logf("StartFull: mitm=%t", mitmActive)

	btun := newBufferedTun(tunFile)

	// Claim the TUN/stack slots only if this session is still the current one.
	// Stop() may have run while the stack was being built: it would have cleared
	// the slots it saw (still nil) and closed the done channel, so an
	// unconditional store here would install a live stack that nothing owns —
	// the classic StartFull-late-vs-Stop interleaving that leaked a running TUN
	// stack until process death.
	e.mu.Lock()
	if !stillCurrent() {
		e.mu.Unlock()
		btun.halt()
		tunFile.Close()
		logf("StartFull: aborted, session was stopped during startup")
		return
	}
	e.tunFile = tunFile
	e.tcpStack = stack
	e.mu.Unlock()

	if err := stack.StartWithEndpoint(newTunLinkEndpoint(btun, uint32(defaultTunMTU)), uint32(defaultTunMTU)); err != nil {
		btun.halt()
		tunFile.Close()
		e.mu.Lock()
		if e.tcpStack == stack {
			e.tcpStack = nil
		}
		if e.tunFile == tunFile {
			e.tunFile = nil
		}
		e.mu.Unlock()
		fail("StartFull: stack start failed: %v", err)
		return
	}

	logf("StartFull: full-network stack running (direct TUN read, async TUN write, mtu=%d)", defaultTunMTU)

	e.trafficTracker.Start()
	if e.logAggregator != nil {
		e.logAggregator.start()
	}

	<-done
	if e.logAggregator != nil {
		e.logAggregator.stop()
	}
	e.trafficTracker.Stop()
	btun.halt()
	// A Stop() that ran before the stack was installed could not reach it (the
	// slot was still nil at the time), so make sure the stack is actually torn
	// down by whoever gets here.
	stack.Stop()
	e.mu.Lock()
	if e.tcpStack == stack {
		e.tcpStack = nil
	}
	if e.tunFile == tunFile {
		e.tunFile = nil
	}
	e.mu.Unlock()
	logf("StartFull: stopped")
}

func newFullTunnelUdpHandler(engine *Engine, filter *MitmFilter, uidr UIDResolver, protectFn func(fd int) bool) UdpFlowHandler {
	return func(conn adapter.UDPConn) {
		defer conn.Close()
		flow := udpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolUDP, flow)
		if engine.isUIDBlocked(uid) {
			engine.logBlockedConnection(flow, ProtocolUDP, "uid_blocked")
			return
		}

		if flow.serverPort == 53 {
			handleDNSOverUDP(conn, engine, uid)
			return
		}

		if engine.shouldBlockEncryptedDNS(flow.serverPort) {
			engine.logBlockedConnection(flow, ProtocolUDP, "blocked_encrypted_dns")
			return
		}
		if !engine.appAllowlistConnectionAllowed(uid, flow.serverIP) {
			engine.logBlockedConnection(flow, ProtocolUDP, "app_allowlist_blocked")
			return
		}
		engine.logConnection(flow, ProtocolUDP)

		if engine.quicDrop.Load() && flow.serverPort == 443 && filter != nil && filter.HasAllowedUIDs() {
			if uid != UIDUnknown && filter.IsUIDAllowed(uid) {
				engine.logBlockedConnection(flow, ProtocolUDP, "quic_forced_tcp")
				return
			}
		}
		outbound := engine.outboundForUID(uid, protectFn)
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

func newFullPassthroughTcpHandler(engine *Engine, uidr UIDResolver, protectFn func(fd int) bool) TcpFlowHandler {
	return func(conn adapter.TCPConn) {
		defer conn.Close()
		flow := tcpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolTCP, flow)
		if engine.isUIDBlocked(uid) {
			engine.logBlockedConnection(flow, ProtocolTCP, "uid_blocked")
			return
		}
		if !engine.appAllowlistConnectionAllowed(uid, flow.serverIP) {
			engine.logBlockedConnection(flow, ProtocolTCP, "app_allowlist_blocked")
			return
		}

		if flow.serverPort == 53 {
			handleDNSOverTCP(conn, engine, uid)
			return
		}

		if engine.shouldBlockEncryptedDNS(flow.serverPort) {
			engine.logBlockedConnection(flow, ProtocolTCP, "blocked_encrypted_dns")
			return
		}
		engine.logConnection(flow, ProtocolTCP)
		clientConn := engine.trafficTracker.WrapClientConn(conn, uid)
		relayDirectFromFlow(clientConn, flow, engine, protectFn)
	}
}

func (e *Engine) SetFilterHttp3(enabled bool) {
	e.quicDrop.Store(enabled)
	logf("SetFilterHttp3: HTTP/3 (QUIC) filtering = %t", enabled)
}

func (e *Engine) SetBlockEncryptedDns(enabled bool) {
	e.blockEncryptedDNS.Store(enabled)
	logf("SetBlockEncryptedDns: encrypted DNS (DoT/853) blocking = %t", enabled)
}

// shouldBlockEncryptedDNS reports whether a flow to port 853 must be blocked.
//
// The three data-plane entry points (full-tunnel UDP, full-tunnel TCP
// passthrough and MITM TCP) used to drop port 853 unconditionally, so the
// "阻断加密 DNS (DoT)" switch only wrote an atomic that nothing read.
func (e *Engine) shouldBlockEncryptedDNS(serverPort int) bool {
	if e == nil || serverPort != encryptedDNSPort {
		return false
	}
	return e.blockEncryptedDNS.Load()
}

const encryptedDNSPort = 853

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
