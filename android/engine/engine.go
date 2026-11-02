// Package tunnel provides a Go-based DNS tunnel engine for Android ad blocking,
// compiled with gomobile bind and invoked directly from Android Kotlin. It runs the
// full-tunnel gVisor data plane (StartFull) and the standalone DNS server
// (StartStandalone), forwarding DNS across multiple protocols (Plain, DoH,
// DoT, DoQ), domain rule matching, and full-network filtering. All exported methods
// adhere strictly to gomobile-compatible types (string, []byte, int, bool).
//
// GC Tuning Rationale:
// Under high-frequency small-packet DNS workloads, Go runtime default GOGC=100 causes
// short, frequent GC cycles resulting in CPU bursts and device heating. GOGC=400 trades
// bounded heap headroom for ~4x fewer GC cycles. A generous soft memory limit
// (engineSoftMemoryLimit) bounds the worst case on low-RAM devices; it sits well
// above the expected live heap so steady-state GC cadence is unchanged.
//
// Concurrency & Teardown Architecture:
// - quicDrop controls whether UDP 443 QUIC traffic is dropped (forcing HTTP/3 fallback
//   to TCP TLS for MITM inspection) or relayed for optimal loading performance.
// - TUN file descriptors are duplicated to establish independent Go runtime ownership.
// - Engine teardown executes outside critical mutex locks to guarantee deadlock-free
//   termination of worker goroutines, the TUN link endpoint and embedded proxy servers.

package tunnel

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"runtime/debug"
	"sync"
	"sync/atomic"

	"github.com/miekg/dns"
)

func init() {
	debug.SetGCPercent(400)
	// Backstop for GOGC=400 on low-RAM devices: without a limit the heap may
	// grow to ~5x the live set before a cycle runs. The limit is generous next to
	// the expected live heap (DNS cache, cert cache, per-flow buffers), so it only
	// takes effect under unusual load; the runtime caps GC CPU near the limit, so
	// it cannot cause an unbounded GC spiral.
	debug.SetMemoryLimit(engineSoftMemoryLimit)
}

const engineSoftMemoryLimit = 128 << 20

type Engine struct {
	protocol    string
	primaryDNS  string
	fallbackDNS string
	dohURL      string
	// responseType is an atomic because the gomobile setters run on the
	// Kotlin/UI thread while the DNS handlers read it from stack goroutines.
	// It used to be a plain field written without e.mu and read without e.mu.
	responseType           atomic.Int32
	dnsConfig              *dnsEngineConfig
	dynamicResponse        dynamicBlockConfig
	dynamicBlocks          dynamicBlockTracker
	logCallback            LogCallback
	batchLogCallback       BatchLogCallback
	logAggregator          *logAggregator
	raceLogCallback        RaceLogCallback
	bootstrapLogCallback   BootstrapLogCallback
	httpLogCallback        HttpLogCallback
	outboundStatusCallback OutboundProxyStatusCallback
	trafficCallback        TrafficCallback
	trafficTracker         *TrafficTracker
	resolver               *Resolver
	dnsCache               *dnsCache
	requestRules           []requestRule
	filterDNS              atomic.Bool
	rewriteRules           map[string]*rewriteEntry
	firewallChecker        FirewallChecker
	appResolver            AppResolver
	appUidResolver         AppUidResolver

	// Lock-free read views for the DNS hot path; writers update them under mu
	// together with the fields they mirror.
	resolverView    atomic.Pointer[Resolver]
	dynamicRespView atomic.Pointer[dynamicBlockConfig]

	mu         sync.Mutex
	callbackMu sync.RWMutex
	running    bool
	tunFile *os.File

	// sessionGen is bumped by every Start*/Stop transition under mu.
	// StartFull releases mu to do its expensive setup (dup, stack allocation,
	// buffered writer) and re-acquires it to publish. A sessionGen captured while
	// holding mu is the only way that late publish can tell "I am still the
	// current session" from "a Stop happened while I was setting up", which the
	// old running-only check could not distinguish. See claimFullTunnelSession.
	sessionGen uint64

	tcpStack *TcpIpStack

	quicDrop          atomic.Bool
	blockEncryptedDNS atomic.Bool
	blockedUIDsMu     sync.RWMutex
	blockedUIDs       map[int]struct{}
	appAllowlist      appAllowlist
	ipDomainCache     *ipDomainCache
	policyEngine      *policyEngine

	stackCertMgr    *CertManager
	stackMitmFilter *MitmFilter
	certDir         string

	uidResolver UIDResolver

	protectFn      func(fd int) bool
	outboundConfig outboundProxyConfig
	flowOutbound   flowOutbound
	// outboundRouteView is the per-session proxy scope snapshot read on the flow path.
	outboundRouteView atomic.Pointer[outboundRoute]

	fullTunnelDone chan struct{}

	standaloneUdp  *dns.Server
	standaloneTcp  *dns.Server
	standaloneUdp6 *dns.Server
	standaloneTcp6 *dns.Server

	totalQueries   atomic.Int64
	blockedQueries atomic.Int64
}

func NewEngine() *Engine {
	e := &Engine{
		dnsCache:       newDNSCache(dnsCacheConfig{Enabled: true}),
		blockedUIDs:    make(map[int]struct{}),
		trafficTracker: newTrafficTracker(),
		logAggregator:  newLogAggregator(),
		policyEngine:   newPolicyEngine(),
		ipDomainCache:  newIPDomainCache(2048),
	}
	e.responseType.Store(int32(ResponseCustomIP))
	e.filterDNS.Store(true)
	// Fail closed: a data plane that never receives SetBlockEncryptedDns keeps
	// blocking DoT, which is what every entry point did before the switch was
	// wired up. The Android layer always pushes the user preference before
	// starting traffic.
	e.blockEncryptedDNS.Store(true)
	return e
}

func (e *Engine) ReleaseTun() {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.tunFile != nil {
		e.tunFile.Close()
		e.tunFile = nil
	}
}

func (e *Engine) Stop() {
	e.mu.Lock()

	// O-104: invalidate any StartFull that is between its unlock and its publish.
	// Stop deliberately does NOT early-return on !e.running: it also releases the
	// DNS-cache cleaner and the MITM certificate cache, both of which exist from
	// NewEngine() and must be freed even when no tunnel ever started (A-017).
	// Everything below is already idempotent, so a second Stop is harmless:
	// each field is nil-ed on the way out, logAggregator/trafficTracker guard with
	// running.Swap, and bufferedTun uses sync.Once.
	e.sessionGen++
	e.running = false

	// Release the DNS cache cleaner goroutine and the MITM certificate cache.
	// Nothing used to stop the cache's 30-second ticker, so every Engine that was
	// dropped without an explicit close leaked one goroutine for the process
	// lifetime — repeatedly in practice, because the CA helper mints a throwaway
	// Engine per certificate call.
	if e.dnsCache != nil {
		e.dnsCache.close()
	}
	if e.stackCertMgr != nil {
		e.stackCertMgr.Release()
	}
	e.stackCertMgr = nil
	e.stackMitmFilter = nil

	stack := e.tcpStack
	e.tcpStack = nil

	fullDone := e.fullTunnelDone
	e.fullTunnelDone = nil

	if e.tunFile != nil {
		e.tunFile.Close()
		e.tunFile = nil
	}

	oldResolver := e.resolver
	e.setResolverLocked(nil)
	oldFlowOutbound := e.flowOutbound
	e.flowOutbound = nil
	e.outboundRouteView.Store(nil)
	if oldFlowOutbound != nil {
		_ = oldFlowOutbound.Close()
	}

	oldUdp := e.standaloneUdp
	e.standaloneUdp = nil

	oldTcp := e.standaloneTcp
	e.standaloneTcp = nil

	oldUdp6 := e.standaloneUdp6
	e.standaloneUdp6 = nil

	oldTcp6 := e.standaloneTcp6
	e.standaloneTcp6 = nil

	e.mu.Unlock()

	if oldUdp != nil {
		oldUdp.Shutdown()
	}
	if oldTcp != nil {
		oldTcp.Shutdown()
	}
	if oldUdp6 != nil {
		oldUdp6.Shutdown()
	}
	if oldTcp6 != nil {
		oldTcp6.Shutdown()
	}
	if oldResolver != nil {
		oldResolver.Shutdown()
	}
	if oldFlowOutbound != nil {
		oldFlowOutbound.Close()
	}

	if fullDone != nil {
		close(fullDone)
	}
	if stack != nil {
		stack.Stop()
	}
	if e.logAggregator != nil {
		e.logAggregator.stop()
	}
	if e.trafficTracker != nil {
		e.trafficTracker.Stop()
	}
	if e.policyEngine != nil {
		e.policyEngine.close()
	}
}

func (e *Engine) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

func (e *Engine) GetStats() string {
	stats := Stats{
		TotalQueries:   e.totalQueries.Load(),
		BlockedQueries: e.blockedQueries.Load(),
	}
	if e.logAggregator != nil {
		stats.DroppedLogs = int64(e.logAggregator.droppedCount())
	}
	data, _ := json.Marshal(stats)
	return string(data)
}

func (e *Engine) writeToTUN(data []byte) {
	e.mu.Lock()
	f := e.tunFile
	e.mu.Unlock()

	if f == nil {
		return
	}
	if _, err := f.Write(data); err != nil {
		logf("TUN write error: %v", err)
	}
}

func logf(format string, args ...interface{}) {
	msg := fmt.Sprintf("[DITING/Go] "+format, args...)
	fmt.Fprintln(os.Stderr, msg)
}

func ResolveHostForProtection(hostname string) string {
	ips, err := net.LookupHost(hostname)
	if err != nil || len(ips) == 0 {
		return ""
	}
	return ips[0]
}

func (e *Engine) domainForIP(ip net.IP) string {
	if e == nil || e.ipDomainCache == nil || ip == nil {
		return ""
	}
	return e.ipDomainCache.get(ip.String())
}
