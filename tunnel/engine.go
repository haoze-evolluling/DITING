// Package tunnel provides a Go-based DNS tunnel engine for Android ad blocking,
// compiled with gomobile bind and invoked directly from Android Kotlin. It handles
// TUN packet processing, DNS query forwarding across multiple protocols (Plain, DoH,
// DoT, DoQ), domain rule matching, and full-network filtering. All exported methods
// adhere strictly to gomobile-compatible types (string, []byte, int, bool).
//
// GC Tuning Rationale:
// Under high-frequency small-packet DNS workloads, Go runtime default GOGC=100 causes
// short, frequent GC cycles resulting in CPU bursts and device heating. GOGC=400 trades
// bounded heap headroom for ~4x fewer GC cycles. A soft memory limit is deliberately
// omitted to prevent continuous GC cycles when live heap approaches the limit.
//
// Concurrency & Teardown Architecture:
// - tcpStackPipe uses atomic.Pointer to allow lock-free DnsInterceptor reads without
//   racing against engine Stop().
// - quicDrop controls whether UDP 443 QUIC traffic is dropped (forcing HTTP/3 fallback
//   to TCP TLS for MITM inspection) or relayed for optimal loading performance.
// - TUN file descriptors are duplicated to establish independent Go runtime ownership.
// - Engine teardown executes outside critical mutex locks to guarantee deadlock-free
//   termination of worker goroutines, interceptor loops, and embedded proxy servers.

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

func init() {
	debug.SetGCPercent(400)
}

type Engine struct {
	protocol               string
	primaryDNS             string
	fallbackDNS            string
	dohURL                 string
	responseType           ResponseType
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
	domainChecker          DomainChecker
	requestRules           []requestRule
	filterDNS              atomic.Bool
	rewriteRules           map[string]*rewriteEntry
	firewallChecker        FirewallChecker
	appResolver            AppResolver
	appUidResolver         AppUidResolver

	adTries        []*MmapTrie
	adTrieIDs      []string
	secTries       []*MmapTrie
	secTrieIDs     []string
	importantTries []*MmapTrie

	adBlooms  []*BloomFilter
	secBlooms []*BloomFilter

	hasNativeRules    atomic.Bool
	hasImportantRules atomic.Bool

	mu         sync.Mutex
	callbackMu sync.RWMutex
	running    bool
	tunFile *os.File

	router      *Router
	interceptor *DnsInterceptor

	tcpStack     *TcpIpStack
	tcpStackPipe atomic.Pointer[packetPipe]
	useTcpStack  atomic.Bool

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

	fullTunnelDone chan struct{}

	standaloneUdp  *dns.Server
	standaloneTcp  *dns.Server
	standaloneUdp6 *dns.Server
	standaloneTcp6 *dns.Server

	totalQueries   atomic.Int64
	blockedQueries atomic.Int64
}

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
		ipDomainCache:  newIPDomainCache(2048),
	}
	e.filterDNS.Store(true)
	e.interceptor = NewDnsInterceptor(e, router)
	return e
}

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

	e.running = false

	if e.interceptor != nil {
		e.interceptor.Stop()
	}

	if e.router != nil {
		e.router.Stop()
	}

	stack := e.tcpStack
	e.tcpStack = nil
	pipe := e.tcpStackPipe.Swap(nil)

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
	if oldFlowOutbound != nil {
		_ = oldFlowOutbound.Close()
	}

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
		if t != nil {
			t.Close()
		}
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

func (e *Engine) domainForIP(ip net.IP) string {
	if e == nil || e.ipDomainCache == nil || ip == nil {
		return ""
	}
	return e.ipDomainCache.get(ip.String())
}
