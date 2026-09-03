// Package tunnel provides a Go-based DNS tunnel engine for Android ad blocking,
// compiled with gomobile bind and called from Android Kotlin. It handles TUN
// packet processing, DNS query forwarding (Plain/DoH/DoT/DoQ), domain blocking,
// and full-network filtering. The exported API uses only gomobile-compatible
// types (string, []byte, int, bool).
package tunnel

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/miekg/dns"
)

// GC tuning for the resident VPN data plane: under high-frequency small-packet
// DNS load the default GOGC=100 triggers short, frequent GC cycles (CPU spikes
// felt as bursty heat); GOGC=400 trades bounded extra heap for ~4x fewer GC
// cycles. A soft memory limit is deliberately NOT set — once live heap
// approaches the limit the runtime enters continuous GC, the exact CPU-burn
// pathology this removes. Revert if GODEBUG=gctrace=1 A/B shows memory growth.
func init() {
	debug.SetGCPercent(400)
}

// Engine is the main DNS tunnel engine.
// All exported methods use gomobile-compatible types.
type Engine struct {
	protocol        string
	primaryDNS      string
	fallbackDNS     string
	dohURL          string
	responseType    ResponseType
	dnsConfig       *dnsEngineConfig
	dynamicResponse dynamicBlockConfig
	dynamicBlocks   dynamicBlockTracker
	logCallback            LogCallback
	batchLogCallback       BatchLogCallback
	logAggregator          *logAggregator
	raceLogCallback        RaceLogCallback
	bootstrapLogCallback   BootstrapLogCallback
	httpLogCallback        HttpLogCallback
	outboundStatusCallback OutboundProxyStatusCallback
	trafficCallback TrafficCallback
	trafficTracker  *TrafficTracker
	resolver        *Resolver
	dnsCache        *dnsCache
	domainChecker   DomainChecker
	requestRules    []requestRule
	filterDNS       atomic.Bool
	rewriteRules    map[string]string
	firewallChecker FirewallChecker
	appResolver     AppResolver
	appUidResolver  AppUidResolver

	adTries   []*MmapTrie
	adTrieIDs []string
	secTries  []*MmapTrie
	secTrieIDs []string
	importantTries []*MmapTrie

	// Bloom filters for fast pre-filtering (skip trie if definitely clean)
	adBlooms  []*BloomFilter
	secBlooms []*BloomFilter

	hasNativeRules    atomic.Bool
	hasImportantRules atomic.Bool

	mu      sync.Mutex
	running bool
	tunFile *os.File

	// Pipeline components
	router      *Router
	interceptor *DnsInterceptor

	// Userspace TCP/IP stack (AdGuard-style model).
	//
	// tcpStackPipe uses atomic.Pointer because the DnsInterceptor hot
	// path reads it without holding e.mu — racing with Stop would be a
	// data race otherwise. The pipe's own Close is panic-free so a
	// stale pointer read + Push is safe (silently drops).
	tcpStack     *TcpIpStack
	tcpStackPipe atomic.Pointer[packetPipe]
	useTcpStack  atomic.Bool

	// quicDrop: when true, browser QUIC (UDP 443) is dropped to force
	// HTTP/3 traffic onto TCP TLS where the MITM can filter it. This gives
	// maximum in-page filtering coverage but makes some sites load
	// partially (browsers retry QUIC before falling back). When false
	// (default), QUIC is relayed so pages load fully/smoothly; DNS-level
	// ad-blocking still applies. Toggled from the UI via SetFilterHttp3.
	quicDrop atomic.Bool
	blockEncryptedDNS atomic.Bool
	blockedUIDsMu     sync.RWMutex
	blockedUIDs       map[int]struct{}
	appAllowlist      appAllowlist
	policyEngine      *policyEngine

	// Stack-mode MITM state. When both are non-nil, the stack uses the
	// MITM TCP handler; otherwise the direct-dial passthrough handler is
	// used.
	stackCertMgr    *CertManager
	stackMitmFilter *MitmFilter
	certDir         string // persistent dir (for CA + goroutine-dump diagnostics)

	// UID resolver — supplied by Kotlin. When nil, flow-level UID lookup
	// falls back to UIDUnknown. Stored on the engine so both the stack
	// (once created) and any future consumer can pull from one place.
	uidResolver UIDResolver

	// protectFn is captured at Start time from the SocketProtector.
	// Handlers that dial outbound (direct flows, resolver fallbacks)
	// use it to ensure the socket bypasses the VPN.
	protectFn func(fd int) bool
	outboundConfig outboundProxyConfig
	flowOutbound flowOutbound

	// fullTunnelDone is created by StartFull and closed by Stop to unblock
	// the full-network engine loop. Nil in the legacy DNS-only
	// modes (StartFull is a separate, isolated data path — see fulltunnel.go).
	fullTunnelDone chan struct{}

	// Standalone Servers
	standaloneUdp *dns.Server
	standaloneTcp *dns.Server
	standaloneUdp6 *dns.Server
	standaloneTcp6 *dns.Server

	// Stats
	totalQueries   atomic.Int64
	blockedQueries atomic.Int64
}

// NewEngine creates a new Engine instance.
func NewEngine() *Engine {
	router := NewRouter()
	e := &Engine{
		responseType:   ResponseCustomIP,
		router:         router,
		dnsCache:       newDNSCache(dnsCacheConfig{Enabled: true}),
		blockedUIDs:    make(map[int]struct{}),
		trafficTracker: newTrafficTracker(),
		logAggregator:  newLogAggregator(),
		policyEngine:   newPolicyEngine(),
	}
	e.filterDNS.Store(true)
	e.interceptor = NewDnsInterceptor(e, router)
	return e
}

// Start begins processing packets from the TUN file descriptor.
// protector is called to protect sockets from VPN routing loop.
//
// This function blocks until Stop() is called.
//
// Pipeline:
//   TUN fd → DnsInterceptor → DNS (port 53) → adblock engine
//                            → non-DNS       → Router → OutboundAdapter
func (e *Engine) Start(fd int, protector SocketProtector) {
	e.mu.Lock()
	if e.running {
		e.mu.Unlock()
		return
	}
	e.running = true
	e.totalQueries.Store(0)
	e.blockedQueries.Store(0)

	var protectFn func(fd int) bool
	if protector != nil {
		protectFn = func(fd int) bool {
			return protector.Protect(fd)
		}
	}
	e.protectFn = protectFn
	e.resolver = NewResolver(protectFn)
	e.resolver.SetRaceLogCallback(e.raceLogCallback)
	e.resolver.SetBootstrapLogCallback(e.bootstrapLogCallback)
	if e.dnsConfig != nil {
		e.resolver.UpdateBootstrap(e.dnsConfig.Bootstrap)
		if err := e.resolver.ConfigureProviders(e.dnsConfig.Mode, e.dnsConfig.Providers); err != nil {
			logf("Start: DNS snapshot rejected: %v", err)
		}
	} else {
		e.resolver.Configure(ParseProtocol(e.protocol), e.primaryDNS, e.fallbackDNS, e.dohURL)
	}
	e.mu.Unlock()

	// Duplicate fd to take proper ownership and avoid Android fdsan unique_fd crashes
	dupFd, err := syscall.Dup(fd)
	if err != nil {
		logf("Failed to dup TUN fd %d: %v", fd, err)
		e.running = false
		return
	}

	e.tunFile = os.NewFile(uintptr(dupFd), "tun")
	if e.tunFile == nil {
		logf("Failed to open TUN fd %d", fd)
		e.running = false
		return
	}

	logf("Engine started, reading from TUN fd=%d", fd)

	// Optional TCP/IP stack (AdGuard-style parallel path): when enabled,
	// non-DNS packets are redirected from the interceptor into the stack
	// instead of the legacy Router. The stack terminates each flow and
	// invokes the registered handler (direct-dial passthrough or MITM).
	if e.useTcpStack.Load() {
		if err := e.startTcpStackParallel(); err != nil {
			logf("TcpIpStack parallel start failed, falling back to legacy path: %v", err)
		}
	}

	if e.logAggregator != nil {
		e.logAggregator.start()
	}

	e.interceptor.Run(e.tunFile)

	logf("Engine stopped")
}

// ReleaseTun closes the engine-owned duplicate of the Android TUN descriptor.
//
// The Android side calls this immediately before closing its original
// ParcelFileDescriptor so the system VPN network can be withdrawn before the
// potentially blocking engine teardown begins. Stop remains responsible for
// all remaining engine cleanup.
func (e *Engine) ReleaseTun() {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.tunFile != nil {
		e.tunFile.Close()
		e.tunFile = nil
	}
}

// Stop stops the engine.
func (e *Engine) Stop() {
	e.mu.Lock()

	e.running = false

	// Stop the interceptor (breaks the read loop)
	if e.interceptor != nil {
		e.interceptor.Stop()
	}

	if e.router != nil {
		e.router.Stop()
	}

	stack := e.tcpStack
	e.tcpStack = nil
	pipe := e.tcpStackPipe.Swap(nil)

	// Unblock the full-network engine loop (StartFull), if running.
	fullDone := e.fullTunnelDone
	e.fullTunnelDone = nil

	if e.tunFile != nil {
		e.tunFile.Close()
		e.tunFile = nil
	}
	
	oldResolver := e.resolver
	e.resolver = nil
	oldFlowOutbound := e.flowOutbound
	e.flowOutbound = nil
	
	for _, t := range e.adTries {
		if t != nil {
			t.Close()
		}
	}
	e.adTries = nil
	e.adTrieIDs = nil

	for _, t := range e.secTries {
		if t != nil {
			t.Close()
		}
	}
	e.secTries = nil
	e.secTrieIDs = nil
	for _, t := range e.importantTries {
		if t != nil { t.Close() }
	}
	e.importantTries = nil

	for _, bf := range e.adBlooms {
		if bf != nil {
			bf.Close()
		}
	}
	e.adBlooms = nil

	for _, bf := range e.secBlooms {
		if bf != nil {
			bf.Close()
		}
	}
	e.secBlooms = nil

	oldUdp := e.standaloneUdp
	e.standaloneUdp = nil
	
	oldTcp := e.standaloneTcp
	e.standaloneTcp = nil

	oldUdp6 := e.standaloneUdp6
	e.standaloneUdp6 = nil

	oldTcp6 := e.standaloneTcp6
	e.standaloneTcp6 = nil

	e.mu.Unlock()

	// Shutdown servers OUTSIDE the lock to prevent deadlocks with ServeDNS handlers
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
	// Tear down the TCP/IP stack outside the lock — Stop() blocks on
	// dispatcher goroutines. Close the pipe first so the outbound
	// writer goroutine unblocks from Pop(), then stop the stack.
	if pipe != nil {
		pipe.Close()
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

// IsRunning returns whether the engine is currently running.
func (e *Engine) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

// GetStats returns engine statistics as JSON.
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

// writeToTUN writes a packet to the TUN device.
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

// logf logs a message (will appear in Android logcat via stderr).
func logf(format string, args ...interface{}) {
	msg := fmt.Sprintf("[BlockAds/Go] "+format, args...)
	fmt.Fprintln(os.Stderr, msg)
}

// ResolveHostForProtection resolves a hostname to an IP address.
// Used by Kotlin to bootstrap DNS server hostname resolution.
func ResolveHostForProtection(hostname string) string {
	ips, err := net.LookupHost(hostname)
	if err != nil || len(ips) == 0 {
		return ""
	}
	return ips[0]
}

// CheckDomainInTrieFile allows Kotlin to individually query a specific pre-compiled
// .trie file to see if it blocks a domain. Used for the "find blocking filter" feature.
func CheckDomainInTrieFile(filePath, domain string) bool {
	if filePath == "" || domain == "" {
		return false
	}
	t, err := LoadMmapTrie(filePath)
	if err != nil {
		return false
	}
	defer t.Close()
	return t.ContainsOrParent(domain)
}
