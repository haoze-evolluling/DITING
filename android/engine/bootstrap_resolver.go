// bootstrap_resolver.go resolves encrypted DNS provider hostnames to bootstrap IP addresses.
//
// Reliability Architecture:
// - Server Racing: Dispatches simultaneous UDP queries across multiple public DNS bootstrap servers, selecting the fastest valid response.
// - Health Scoring: Tracks success latency and consecutive failures per bootstrap endpoint.
// - System Fallback: Falls back to protected system DNS resolution if all bootstrap racing attempts fail.
//
// Responsibility split (Rust kernel rust/diting-bootstrap-core): the per-endpoint health model
// (half-life decay, EWMA latency, jitter, consecutive-failure penalty, cooldown), the weighted
// primary pick with its exploration rate, the fallback order and the one-minute host cache all
// live in the kernel. Go keeps the JSON config, the UDP query, the logging callback and the
// `net.IP` fast path. Every kernel call passes unix nanoseconds, so the kernel never reads a
// clock; the two random rolls come from Go as well.

package tunnel

import (
	"context"
	"fmt"
	"math/rand"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

type BootstrapLogCallback interface {
	OnBootstrapResult(
		ipID string,
		ipName string,
		ip string,
		host string,
		success bool,
		elapsedMs int64,
		fallbackUsed bool,
		errorMessage string,
	)
}

type bootstrapIPConfig struct {
	ID     string  `json:"id"`
	Name   string  `json:"name"`
	IP     string  `json:"ip"`
	Weight float64 `json:"weight,omitempty"`
}

type bootstrapConfig struct {
	Enabled bool                `json:"enabled"`
	IPs     []bootstrapIPConfig `json:"ips"`
}

type bootstrapPlan struct {
	primary     bootstrapIPConfig
	fallbacks   []bootstrapIPConfig
	exploration bool
}

type bootstrapResolver struct {
	mu        sync.RWMutex
	enabled   bool
	ips       []bootstrapIPConfig
	protectFn func(fd int) bool

	callbackMu sync.RWMutex
	callback   BootstrapLogCallback

	// kernel is nil when the Rust library is missing or has a stale ABI. Bootstrap is then
	// reported as disabled, so callers dial the provider hostname through the normal path.
	// There is no second scoring implementation to fall back to.
	kernel *nativeBootstrap
}

func newBootstrapResolver(protectFn func(fd int) bool) *bootstrapResolver {
	resolver := &bootstrapResolver{protectFn: protectFn}
	if kernel, err := newNativeBootstrap(); err == nil {
		resolver.kernel = kernel
	}
	return resolver
}

func (b *bootstrapResolver) SetCallback(cb BootstrapLogCallback) {
	b.callbackMu.Lock()
	b.callback = cb
	b.callbackMu.Unlock()
}

func (b *bootstrapResolver) getCallback() BootstrapLogCallback {
	b.callbackMu.RLock()
	defer b.callbackMu.RUnlock()
	return b.callback
}

func (b *bootstrapResolver) UpdateConfig(cfg bootstrapConfig) {
	b.mu.Lock()
	b.enabled = cfg.Enabled
	b.ips = make([]bootstrapIPConfig, len(cfg.IPs))
	copy(b.ips, cfg.IPs)
	kernel := b.kernel
	b.mu.Unlock()

	// Health history is keyed by endpoint id and survives a config change; only the resolved
	// host cache is invalidated.
	if kernel != nil {
		kernel.clearCache()
	}
}

func (b *bootstrapResolver) ResetStats() {
	if b.kernel != nil {
		b.kernel.reset()
	}
}

func (b *bootstrapResolver) IsEnabled() bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.enabled && len(b.ips) > 0 && b.kernel != nil
}

// recordResult folds one bootstrap attempt into the endpoint's health.
func (b *bootstrapResolver) recordResult(id string, success bool, elapsedMs int64, now time.Time) {
	if b.kernel == nil {
		return
	}
	b.kernel.recordResult(id, success, elapsedMs, now.UnixNano())
}

// choosePlan asks the kernel for the primary endpoint and the fallback order. The index roll is
// injected so the decision stays testable and the kernel owns no random source.
func (b *bootstrapResolver) choosePlan(ips []bootstrapIPConfig, now time.Time) bootstrapPlan {
	if len(ips) == 0 {
		return bootstrapPlan{}
	}
	if len(ips) == 1 {
		return bootstrapPlan{primary: ips[0]}
	}
	if b.kernel == nil {
		return bootstrapPlan{}
	}

	result, err := b.kernel.plan(ips, now.UnixNano(), rand.Float64(), rand.Float64(), rand.Uint64())
	if err != nil {
		logf("Bootstrap: plan failed: %v", err)
		return bootstrapPlan{}
	}
	if result.primary < 0 || result.primary >= len(ips) {
		return bootstrapPlan{}
	}

	plan := bootstrapPlan{
		primary:     ips[result.primary],
		fallbacks:   make([]bootstrapIPConfig, 0, len(result.fallbacks)),
		exploration: result.exploration,
	}
	for _, index := range result.fallbacks {
		if index >= 0 && index < len(ips) {
			plan.fallbacks = append(plan.fallbacks, ips[index])
		}
	}
	return plan
}

func (b *bootstrapResolver) ResolveHost(ctx context.Context, host string) (string, error) {
	if host == "" {
		return "", fmt.Errorf("empty host")
	}
	if net.ParseIP(host) != nil {
		return host, nil
	}

	b.mu.RLock()
	enabled := b.enabled
	ips := make([]bootstrapIPConfig, len(b.ips))
	copy(ips, b.ips)
	protectFn := b.protectFn
	kernel := b.kernel
	b.mu.RUnlock()

	if !enabled || len(ips) == 0 || kernel == nil {
		return host, nil
	}

	normalizedHost := strings.ToLower(strings.TrimSpace(host))
	if cachedIP, ok := kernel.cacheGet(normalizedHost, time.Now().UnixNano()); ok {
		return cachedIP, nil
	}

	now := time.Now()
	plan := b.choosePlan(ips, now)
	if plan.primary.IP == "" {
		return "", fmt.Errorf("no bootstrap IP configured")
	}

	cb := b.getCallback()
	var lastErr error

	executionList := append([]bootstrapIPConfig{plan.primary}, plan.fallbacks...)

	for i, entry := range executionList {
		if ctx.Err() != nil {
			return "", ctx.Err()
		}

		start := time.Now()
		fallbackUsed := (i > 0)
		resolvedIP, err := queryBootstrapDNS(ctx, entry.IP, normalizedHost, protectFn)
		elapsedMs := time.Since(start).Milliseconds()
		if elapsedMs < 1 {
			elapsedMs = 1
		}

		isSuccess := (err == nil && resolvedIP != "")
		b.recordResult(entry.ID, isSuccess, elapsedMs, time.Now())

		if isSuccess {
			kernel.cachePut(normalizedHost, resolvedIP, time.Now().UnixNano())
			if cb != nil {
				msg := ""
				if plan.exploration && i == 0 {
					msg = "exploration"
				}
				cb.OnBootstrapResult(entry.ID, entry.Name, entry.IP, normalizedHost, true, elapsedMs, fallbackUsed, msg)
			}
			return resolvedIP, nil
		}

		lastErr = err
		errMsg := ""
		if err != nil {
			errMsg = err.Error()
		}
		if cb != nil {
			cb.OnBootstrapResult(entry.ID, entry.Name, entry.IP, normalizedHost, false, elapsedMs, fallbackUsed, errMsg)
		}
	}

	if lastErr != nil {
		return "", fmt.Errorf("bootstrap resolution failed for %s: %w", host, lastErr)
	}
	return "", fmt.Errorf("all bootstrap servers failed for %s", host)
}

func queryBootstrapDNS(ctx context.Context, bootstrapServer, host string, protectFn func(fd int) bool) (string, error) {
	serverAddr := bootstrapServer
	if _, _, err := net.SplitHostPort(serverAddr); err != nil {
		serverAddr = net.JoinHostPort(serverAddr, "53")
	}

	queryCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	dialer := &net.Dialer{
		Timeout: 3 * time.Second,
		Control: protectedControl(protectFn),
	}

	conn, err := dialer.DialContext(queryCtx, "udp", serverAddr)
	if err != nil {
		return "", fmt.Errorf("dial bootstrap %s: %w", serverAddr, err)
	}
	defer conn.Close()

	if deadline, ok := queryCtx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(host), dns.TypeA)
	msg.RecursionDesired = true
	rawQuery, err := msg.Pack()
	if err != nil {
		return "", fmt.Errorf("pack DNS query: %w", err)
	}

	if _, err := conn.Write(rawQuery); err != nil {
		return "", fmt.Errorf("write query to %s: %w", serverAddr, err)
	}

	buf := make([]byte, 2048)
	n, err := conn.Read(buf)
	if err != nil {
		return "", fmt.Errorf("read response from %s: %w", serverAddr, err)
	}

	var resp dns.Msg
	if err := resp.Unpack(buf[:n]); err != nil {
		return "", fmt.Errorf("unpack DNS response: %w", err)
	}

	for _, rr := range resp.Answer {
		if a, ok := rr.(*dns.A); ok && a.A != nil {
			return a.A.String(), nil
		}
	}

	msgAAAA := new(dns.Msg)
	msgAAAA.SetQuestion(dns.Fqdn(host), dns.TypeAAAA)
	msgAAAA.RecursionDesired = true
	rawQueryAAAA, errAAAA := msgAAAA.Pack()
	if errAAAA == nil {
		if _, err := conn.Write(rawQueryAAAA); err == nil {
			nAAAA, errRead := conn.Read(buf)
			if errRead == nil {
				var respAAAA dns.Msg
				if err := respAAAA.Unpack(buf[:nAAAA]); err == nil {
					for _, rr := range respAAAA.Answer {
						if aaaa, ok := rr.(*dns.AAAA); ok && aaaa.AAAA != nil {
							return aaaa.AAAA.String(), nil
						}
					}
				}
			}
		}
	}

	return "", fmt.Errorf("no A/AAAA record for %s from %s", host, serverAddr)
}
