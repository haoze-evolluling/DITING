package tunnel

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// BootstrapLogCallback is implemented by Android/Kotlin to receive bootstrap resolution metrics.
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

type cachedBootstrapHost struct {
	ip        string
	expiresAt time.Time
}

const (
	bsDefaultLatencyMs         = 250.0
	bsMinLatencyMs             = 20.0
	bsMaxLatencyMs             = 5000.0
	bsMinWeight                = 0.05
	bsMaxWeight                = 3.0
	bsJitterWeight             = 0.5
	bsCooldownPenalty          = 0.1
	bsConsecutiveFailPenalty   = 0.2
	bsEwmaAlpha                = 0.25
	bsJitterAlpha              = 0.20
	bsBaseExplorationRate      = 0.02
	bsLowSampleExplorationRate = 0.08
	bsRecoveryExplorationRate  = 0.10
	bsLowSampleThreshold       = 10.0
	bsCooldownFailureThreshold = 3
	bsCooldownDuration         = 30 * time.Second
	bsHealthHalfLifeDuration   = 30 * time.Minute
)

type bootstrapIPHealth struct {
	mu                  sync.RWMutex
	successes           int
	failures            int
	ewmaMs              float64
	jitterMs            float64
	consecutiveFailures int
	cooldownUntil       time.Time
	decayedSuccesses    float64
	decayedFailures     float64
	lastUpdatedAt       time.Time
}

func newBootstrapIPHealth() *bootstrapIPHealth {
	return &bootstrapIPHealth{
		ewmaMs:        bsDefaultLatencyMs,
		lastUpdatedAt: time.Now(),
	}
}

func (h *bootstrapIPHealth) applyDecayLocked(now time.Time) {
	if h.lastUpdatedAt.IsZero() {
		h.lastUpdatedAt = now
		return
	}
	elapsed := now.Sub(h.lastUpdatedAt)
	if elapsed <= 0 {
		return
	}
	factor := math.Pow(0.5, float64(elapsed)/float64(bsHealthHalfLifeDuration))
	h.decayedSuccesses *= factor
	h.decayedFailures *= factor
	h.lastUpdatedAt = now
}

func (h *bootstrapIPHealth) RecordResult(success bool, elapsedMs int64, now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.applyDecayLocked(now)

	safeElapsed := float64(elapsedMs)
	if safeElapsed < 1.0 {
		safeElapsed = 1.0
	}

	if success {
		h.successes++
		h.decayedSuccesses += 1.0
		h.consecutiveFailures = 0
		h.cooldownUntil = time.Time{}

		h.ewmaMs = h.ewmaMs*(1.0-bsEwmaAlpha) + safeElapsed*bsEwmaAlpha
		h.jitterMs = h.jitterMs*(1.0-bsJitterAlpha) + math.Abs(safeElapsed-h.ewmaMs)*bsJitterAlpha
	} else {
		h.failures++
		h.decayedFailures += 1.0
		h.consecutiveFailures++
		if h.consecutiveFailures >= bsCooldownFailureThreshold {
			h.cooldownUntil = now.Add(bsCooldownDuration)
		}
	}
	h.lastUpdatedAt = now
}

type bootstrapScore struct {
	entry       bootstrapIPConfig
	weight      float64
	coolingDown bool
	sampleCount float64
}

func (h *bootstrapIPHealth) GetScore(entry bootstrapIPConfig, now time.Time) bootstrapScore {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.applyDecayLocked(now)

	decayedAttempts := h.decayedSuccesses + h.decayedFailures
	coolingDown := !h.cooldownUntil.IsZero() && now.Before(h.cooldownUntil)

	if decayedAttempts <= 0 {
		initialWeight := entry.Weight
		if initialWeight <= 0 {
			initialWeight = 1.0
		}
		return bootstrapScore{
			entry:       entry,
			weight:      initialWeight,
			coolingDown: coolingDown,
			sampleCount: 0,
		}
	}

	correctness := (h.decayedSuccesses + 2.0) / (decayedAttempts + 3.0)

	speed := 1.0
	if h.successes > 0 {
		effectiveLatency := h.ewmaMs + h.jitterMs*bsJitterWeight
		if effectiveLatency < bsMinLatencyMs {
			effectiveLatency = bsMinLatencyMs
		} else if effectiveLatency > bsMaxLatencyMs {
			effectiveLatency = bsMaxLatencyMs
		}
		speed = bsDefaultLatencyMs / effectiveLatency
	}

	cPenalty := 1.0
	if coolingDown {
		cPenalty = bsCooldownPenalty
	}

	fPenalty := 1.0 / (1.0 + float64(h.consecutiveFailures)*bsConsecutiveFailPenalty)

	w := correctness * speed * cPenalty * fPenalty
	if w < bsMinWeight {
		w = bsMinWeight
	} else if w > bsMaxWeight {
		w = bsMaxWeight
	}

	return bootstrapScore{
		entry:       entry,
		weight:      w,
		coolingDown: coolingDown,
		sampleCount: decayedAttempts,
	}
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

	cacheMu sync.RWMutex
	cache   map[string]*cachedBootstrapHost

	callbackMu sync.RWMutex
	callback   BootstrapLogCallback

	healthMu  sync.RWMutex
	healthMap map[string]*bootstrapIPHealth
}

func newBootstrapResolver(protectFn func(fd int) bool) *bootstrapResolver {
	return &bootstrapResolver{
		protectFn: protectFn,
		cache:     make(map[string]*cachedBootstrapHost),
		healthMap: make(map[string]*bootstrapIPHealth),
	}
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
	b.mu.Unlock()

	// Clear cache on config change
	b.cacheMu.Lock()
	b.cache = make(map[string]*cachedBootstrapHost)
	b.cacheMu.Unlock()
}

func (b *bootstrapResolver) ResetStats() {
	b.healthMu.Lock()
	b.healthMap = make(map[string]*bootstrapIPHealth)
	b.healthMu.Unlock()

	b.cacheMu.Lock()
	b.cache = make(map[string]*cachedBootstrapHost)
	b.cacheMu.Unlock()
}

func (b *bootstrapResolver) IsEnabled() bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.enabled && len(b.ips) > 0
}

func (b *bootstrapResolver) getOrCreateHealth(id string) *bootstrapIPHealth {
	b.healthMu.RLock()
	h, ok := b.healthMap[id]
	b.healthMu.RUnlock()
	if ok {
		return h
	}

	b.healthMu.Lock()
	defer b.healthMu.Unlock()
	if h, ok := b.healthMap[id]; ok {
		return h
	}
	h = newBootstrapIPHealth()
	b.healthMap[id] = h
	return h
}

func (b *bootstrapResolver) getCached(host string) (string, bool) {
	b.cacheMu.RLock()
	defer b.cacheMu.RUnlock()
	entry, ok := b.cache[host]
	if !ok {
		return "", false
	}
	if time.Now().After(entry.expiresAt) {
		return "", false
	}
	return entry.ip, true
}

func (b *bootstrapResolver) putCached(host string, ip string) {
	b.cacheMu.Lock()
	b.cache[host] = &cachedBootstrapHost{
		ip:        ip,
		expiresAt: time.Now().Add(60 * time.Second),
	}
	b.cacheMu.Unlock()
}

func (b *bootstrapResolver) choosePlan(ips []bootstrapIPConfig, now time.Time) bootstrapPlan {
	if len(ips) == 0 {
		return bootstrapPlan{}
	}
	if len(ips) == 1 {
		return bootstrapPlan{primary: ips[0]}
	}

	scores := make([]bootstrapScore, len(ips))
	for i, entry := range ips {
		health := b.getOrCreateHealth(entry.ID)
		scores[i] = health.GetScore(entry, now)
	}

	candidates := make([]bootstrapScore, 0, len(scores))
	hasCoolingDown := false
	hasLowSample := false
	for _, s := range scores {
		if s.coolingDown {
			hasCoolingDown = true
		} else {
			candidates = append(candidates, s)
		}
		if s.sampleCount < bsLowSampleThreshold {
			hasLowSample = true
		}
	}
	if len(candidates) == 0 {
		candidates = scores
	}

	explorationRate := bsBaseExplorationRate
	if hasCoolingDown {
		explorationRate = bsRecoveryExplorationRate
	} else if hasLowSample {
		explorationRate = bsLowSampleExplorationRate
	}

	exploration := rand.Float64() < explorationRate
	var primary bootstrapScore
	if exploration {
		primary = candidates[rand.Intn(len(candidates))]
	} else {
		primary = chooseWeighted(candidates)
	}

	remaining := make([]bootstrapScore, 0, len(scores)-1)
	for _, s := range scores {
		if s.entry.ID != primary.entry.ID {
			remaining = append(remaining, s)
		}
	}
	sort.SliceStable(remaining, func(i, j int) bool {
		return remaining[i].weight > remaining[j].weight
	})

	fallbacks := make([]bootstrapIPConfig, len(remaining))
	for i, s := range remaining {
		fallbacks[i] = s.entry
	}

	return bootstrapPlan{
		primary:     primary.entry,
		fallbacks:   fallbacks,
		exploration: exploration,
	}
}

func chooseWeighted(candidates []bootstrapScore) bootstrapScore {
	var total float64
	for _, c := range candidates {
		if c.weight > 0 {
			total += c.weight
		}
	}
	if total <= 0 {
		return candidates[0]
	}

	r := rand.Float64() * total
	for _, c := range candidates {
		if c.weight > 0 {
			r -= c.weight
			if r <= 0 {
				return c
			}
		}
	}
	return candidates[len(candidates)-1]
}

// ResolveHost resolves host to an IP address using Bootstrap DNS IPs with dynamic weighted plan.
// If host is already an IP or bootstrap is disabled, it returns host as-is.
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
	b.mu.RUnlock()

	if !enabled || len(ips) == 0 {
		return host, nil
	}

	normalizedHost := strings.ToLower(strings.TrimSpace(host))
	if cachedIP, ok := b.getCached(normalizedHost); ok {
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

		health := b.getOrCreateHealth(entry.ID)
		isSuccess := (err == nil && resolvedIP != "")
		health.RecordResult(isSuccess, elapsedMs, time.Now())

		if isSuccess {
			b.putCached(normalizedHost, resolvedIP)
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

	// If no A record, try AAAA query
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

