package tunnel

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
)

// DNSProtocol represents the DNS transport protocol.
type DNSProtocol int

const (
	ProtocolPlain DNSProtocol = iota
	ProtocolDoH
	ProtocolDoT
	ProtocolDoQ
)

// ParseProtocol converts a string to DNSProtocol.
func ParseProtocol(s string) DNSProtocol {
	switch strings.ToUpper(s) {
	case "DOH":
		return ProtocolDoH
	case "DOT":
		return ProtocolDoT
	case "DOQ":
		return ProtocolDoQ
	default:
		return ProtocolPlain
	}
}

const (
	queryTimeoutPlain = 5 * time.Second
	queryTimeoutDoH   = 5 * time.Second
	queryTimeoutDoT   = 5 * time.Second
	queryTimeoutDoQ   = 5 * time.Second
	connectTimeout    = 3 * time.Second
)

// Resolver handles DNS query forwarding across multiple protocols.
type Resolver struct {
	mu sync.RWMutex

	primaryServer   string
	fallbackServer  string
	dohURL          string
	protocol        DNSProtocol
	protectSocketFn func(fd int) bool
	outbound        flowOutbound

	// HTTP client for DoH (reusable)
	httpClient *http.Client
	// QUIC connection for DoQ (reusable)
	quicConn   quic.Connection
	quicMu     sync.Mutex
	quicServer string

	// DoT connection pool (reusable)
	dotMu    sync.Mutex
	dotConns map[string][]*dotConnEntry

	closed atomic.Bool

	bootstrap *bootstrapResolver

	providerSnapshot *resolverSnapshot
	statsMapMu       sync.Mutex
	providerStatsMap map[string]*providerStats
	raceLogCallback  RaceLogCallback
	bootstrapCallback BootstrapLogCallback
}

// NewResolver creates a new DNS resolver.
func NewResolver(protectFn func(fd int) bool) *Resolver {
	outbound := newFlowOutbound(outboundProxyConfig{}, protectFn, nil)
	bs := newBootstrapResolver(protectFn)
	return &Resolver{
		protectSocketFn:  protectFn,
		outbound:         outbound,
		bootstrap:        bs,
		httpClient:       buildDoHClient(outbound, bs),
		dotConns:         make(map[string][]*dotConnEntry),
		providerStatsMap: make(map[string]*providerStats),
	}
}

// SetRaceLogCallback sets the callback for DNS race results.
func (r *Resolver) SetRaceLogCallback(cb RaceLogCallback) {
	r.mu.Lock()
	r.raceLogCallback = cb
	r.mu.Unlock()
}

// SetBootstrapLogCallback sets the callback for Bootstrap DNS results.
func (r *Resolver) SetBootstrapLogCallback(cb BootstrapLogCallback) {
	r.mu.Lock()
	r.bootstrapCallback = cb
	if r.bootstrap != nil {
		r.bootstrap.SetCallback(cb)
	}
	snapshot := r.providerSnapshot
	r.mu.Unlock()
	if snapshot != nil {
		snapshot.mu.Lock()
		for _, p := range snapshot.providers {
			if p.resolver != nil {
				p.resolver.SetBootstrapLogCallback(cb)
			}
		}
		snapshot.mu.Unlock()
	}
}

// UpdateBootstrap updates the bootstrap resolver configuration.
func (r *Resolver) UpdateBootstrap(cfg bootstrapConfig) {
	r.mu.Lock()
	if r.bootstrap == nil {
		r.bootstrap = newBootstrapResolver(r.protectSocketFn)
		if r.bootstrapCallback != nil {
			r.bootstrap.SetCallback(r.bootstrapCallback)
		}
	}
	r.bootstrap.UpdateConfig(cfg)
	snapshot := r.providerSnapshot
	r.mu.Unlock()
	if snapshot != nil {
		snapshot.mu.Lock()
		for _, p := range snapshot.providers {
			if p.resolver != nil {
				p.resolver.UpdateBootstrap(cfg)
			}
		}
		snapshot.mu.Unlock()
	}
}

// ResetBootstrapStats clears health statistics and host cache in bootstrap resolver.
func (r *Resolver) ResetBootstrapStats() {
	r.mu.Lock()
	if r.bootstrap != nil {
		r.bootstrap.ResetStats()
	}
	snapshot := r.providerSnapshot
	r.mu.Unlock()
	if snapshot != nil {
		snapshot.mu.Lock()
		for _, p := range snapshot.providers {
			if p.resolver != nil {
				p.resolver.ResetBootstrapStats()
			}
		}
		snapshot.mu.Unlock()
	}
}

func (r *Resolver) notifyRaceLog(
	queryName string,
	queryType uint16,
	strategy string,
	providerCount int,
	success bool,
	elapsedMs int64,
	selectedProviderID string,
	selectedElapsedMs int64,
	winnerProviderID string,
	winnerElapsedMs int64,
	fallbackUsed bool,
	fallbackSuccess bool,
	errorMessage string,
) {
	r.mu.RLock()
	cb := r.raceLogCallback
	r.mu.RUnlock()
	if cb != nil {
		cb.OnRaceResult(
			queryName,
			int(queryType),
			strategy,
			providerCount,
			success,
			elapsedMs,
			selectedProviderID,
			selectedElapsedMs,
			winnerProviderID,
			winnerElapsedMs,
			fallbackUsed,
			fallbackSuccess,
			errorMessage,
		)
	}
}

func (r *Resolver) setOutbound(outbound flowOutbound) {
	if outbound == nil {
		outbound = newFlowOutbound(outboundProxyConfig{}, r.protectSocketFn, nil)
	}
	r.mu.Lock()
	oldClient := r.httpClient
	r.outbound = outbound
	r.httpClient = buildDoHClient(outbound, r.bootstrap)
	snapshot := r.providerSnapshot
	r.mu.Unlock()
	if oldClient != nil {
		oldClient.CloseIdleConnections()
	}
	if snapshot != nil {
		snapshot.mu.Lock()
		for _, p := range snapshot.providers {
			if p.resolver != nil {
				p.resolver.setOutbound(outbound)
			}
		}
		snapshot.mu.Unlock()
	}
}

// Configure updates the resolver's DNS settings.
func (r *Resolver) Configure(protocol DNSProtocol, primary, fallback, dohURL string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.protocol = protocol
	r.primaryServer = primary
	r.fallbackServer = fallback
	r.dohURL = dohURL

	// Reset DoQ connection if server changed
	r.quicMu.Lock()
	if r.quicConn != nil && r.quicServer != dohURL {
		r.quicConn.CloseWithError(quic.ApplicationErrorCode(0), "config change")
		r.quicConn = nil
	}
	r.quicMu.Unlock()
}

// ConfigureProviders swaps the complete provider set used by multi-strategy mode.
func (r *Resolver) ConfigureProviders(mode string, configs []dnsProviderConfig) error {
	r.statsMapMu.Lock()
	if r.providerStatsMap == nil {
		r.providerStatsMap = make(map[string]*providerStats)
	}
	providers := make([]*configuredProvider, 0, len(configs))
	for _, cfg := range configs {
		child := NewResolver(r.protectSocketFn)
		child.setOutbound(r.outbound)
		if r.bootstrap != nil {
			child.bootstrap = r.bootstrap
			child.httpClient = buildDoHClient(r.outbound, r.bootstrap)
		}
		if r.bootstrapCallback != nil {
			child.SetBootstrapLogCallback(r.bootstrapCallback)
		}
		proto := ParseProtocol(cfg.Protocol)
		child.Configure(proto, cfg.Server, "", cfg.URL)

		statsKey := cfg.ID
		if statsKey == "" {
			statsKey = fmt.Sprintf("%s:%s:%s", cfg.Protocol, cfg.Server, cfg.URL)
		}
		stats := r.providerStatsMap[statsKey]
		if stats == nil {
			stats = newProviderStats()
			r.providerStatsMap[statsKey] = stats
		}

		providers = append(providers, &configuredProvider{
			id:       cfg.ID,
			protocol: proto,
			server:   cfg.Server,
			dohURL:   cfg.URL,
			resolver: child,
			stats:    stats,
		})
	}
	r.statsMapMu.Unlock()

	if len(providers) == 0 {
		return fmt.Errorf("DNS snapshot has no providers")
	}
	next := &resolverSnapshot{providers: providers, mode: mode}
	r.mu.Lock()
	old := r.providerSnapshot
	r.providerSnapshot = next
	r.mu.Unlock()
	if old != nil {
		old.retire()
	}
	return nil
}

// Resolve forwards a DNS query and returns the response.
func (r *Resolver) Resolve(rawQuery []byte) ([]byte, error) {
	r.mu.RLock()
	snapshot := r.providerSnapshot
	acquiredSnapshot := snapshot != nil && snapshot.acquire()
	protocol := r.protocol
	primary := r.primaryServer
	fallback := r.fallbackServer
	dohURL := r.dohURL
	r.mu.RUnlock()
	if acquiredSnapshot {
		defer snapshot.release()
		return r.resolveConfigured(rawQuery, snapshot)
	}

	resp, err := r.query(rawQuery, protocol, primary, dohURL)
	if err == nil {
		return resp, nil
	}

	// Try fallback with PLAIN protocol if configured and different
	if fallback != "" && fallback != primary {
		resp, err2 := r.query(rawQuery, ProtocolPlain, fallback, "")
		if err2 == nil {
			return resp, nil
		}
		return nil, fmt.Errorf("primary (%s): %w; fallback (%s): %v", primary, err, fallback, err2)
	}

	return nil, err
}

// query performs a DNS query using the specified protocol with a background context.
func (r *Resolver) query(rawQuery []byte, protocol DNSProtocol, server, dohURL string) ([]byte, error) {
	return r.queryWithContext(context.Background(), rawQuery, protocol, server, dohURL)
}

func (r *Resolver) queryWithContext(ctx context.Context, rawQuery []byte, protocol DNSProtocol, server, dohURL string) ([]byte, error) {
	switch protocol {
	case ProtocolDoH:
		return r.queryDoHContext(ctx, rawQuery, dohURL)
	case ProtocolDoT:
		return r.queryDoTContext(ctx, rawQuery, server)
	case ProtocolDoQ:
		return r.queryDoQContext(ctx, rawQuery, dohURL)
	default:
		return r.queryPlainContext(ctx, rawQuery, server)
	}
}

// ResolveARecord resolves a domain's A record via a protected plain DNS query.
// Used as the direct fallback for HTTPS passthrough host resolution.
func (r *Resolver) ResolveARecord(domain, dnsServer string) (net.IP, error) {
	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	msg.RecursionDesired = true

	rawQuery, err := msg.Pack()
	if err != nil {
		return nil, fmt.Errorf("pack query: %w", err)
	}

	resp, err := r.queryPlain(rawQuery, dnsServer)
	if err != nil {
		return nil, err
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		return nil, fmt.Errorf("unpack response: %w", err)
	}

	for _, rr := range respMsg.Answer {
		if a, ok := rr.(*dns.A); ok {
			return a.A.To4(), nil
		}
	}

	return nil, fmt.Errorf("no A record for %s", domain)
}

// Shutdown cleans up resolver resources.
func (r *Resolver) Shutdown() {
	if !r.closed.CompareAndSwap(false, true) {
		return
	}
	r.mu.Lock()
	snapshot := r.providerSnapshot
	r.providerSnapshot = nil
	r.mu.Unlock()
	if snapshot != nil {
		snapshot.retire()
	}
	r.resetQUICConn()
	r.httpClient.CloseIdleConnections()
	r.closeDoTConns()
}
