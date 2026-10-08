package core

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

// BootstrapServer 定义单个引导 DNS 服务器配置
type BootstrapServer struct {
	ID      string  `json:"id"`
	Name    string  `json:"name"`
	Address string  `json:"address"`
	Weight  float64 `json:"weight,omitempty"`
}

// BootstrapConfig 定义引导解析器配置
type BootstrapConfig struct {
	Enabled bool              `json:"enabled"`
	Servers []BootstrapServer `json:"servers"`
}

// ValidateBootstrapConfig 校验 Bootstrap 配置合法性，要求服务器地址必须为有效 IP
func ValidateBootstrapConfig(cfg BootstrapConfig) error {
	for i, s := range cfg.Servers {
		addr := strings.TrimSpace(s.Address)
		if addr == "" {
			return fmt.Errorf("bootstrap server %d: address is empty", i+1)
		}
		host := addr
		if h, _, err := net.SplitHostPort(addr); err == nil {
			host = h
		}
		cleanHost := strings.Trim(host, "[]")
		if net.ParseIP(cleanHost) == nil {
			return fmt.Errorf("bootstrap server %q: address %q must be a valid IP address", s.ID, s.Address)
		}
	}
	return nil
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
	bsDefaultCacheTTL          = 60 * time.Second
)

type bootstrapHealth struct {
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

func newBootstrapHealth() *bootstrapHealth {
	return &bootstrapHealth{
		ewmaMs:        bsDefaultLatencyMs,
		lastUpdatedAt: time.Now(),
	}
}

func (h *bootstrapHealth) applyDecayLocked(now time.Time) {
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

func (h *bootstrapHealth) RecordResult(success bool, elapsedMs int64, now time.Time) {
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
	entry       BootstrapServer
	weight      float64
	coolingDown bool
	sampleCount float64
}

func (h *bootstrapHealth) GetScore(entry BootstrapServer, now time.Time) bootstrapScore {
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
	primary     BootstrapServer
	fallbacks   []BootstrapServer
	exploration bool
}

// BootstrapResolver 解决加密上游 (DoH/DoT) 域名到 IP 的引导解析
type BootstrapResolver struct {
	mu        sync.RWMutex
	enabled   bool
	servers   []BootstrapServer
	cacheMu   sync.RWMutex
	cache     map[string]*cachedBootstrapHost
	healthMu  sync.RWMutex
	healthMap map[string]*bootstrapHealth
}

// NewBootstrapResolver 创建引导解析器
func NewBootstrapResolver(cfg BootstrapConfig) *BootstrapResolver {
	br := &BootstrapResolver{
		enabled:   cfg.Enabled,
		servers:   cfg.Servers,
		cache:     make(map[string]*cachedBootstrapHost),
		healthMap: make(map[string]*bootstrapHealth),
	}
	return br
}

// UpdateConfig 更新引导配置
func (b *BootstrapResolver) UpdateConfig(cfg BootstrapConfig) {
	b.mu.Lock()
	b.enabled = cfg.Enabled
	b.servers = make([]BootstrapServer, len(cfg.Servers))
	copy(b.servers, cfg.Servers)
	b.mu.Unlock()

	b.cacheMu.Lock()
	b.cache = make(map[string]*cachedBootstrapHost)
	b.cacheMu.Unlock()
}

// ResetStats 清空健康评分与缓存
func (b *BootstrapResolver) ResetStats() {
	b.healthMu.Lock()
	b.healthMap = make(map[string]*bootstrapHealth)
	b.healthMu.Unlock()

	b.cacheMu.Lock()
	b.cache = make(map[string]*cachedBootstrapHost)
	b.cacheMu.Unlock()
}

// IsEnabled 检查引导解析器是否已启用
func (b *BootstrapResolver) IsEnabled() bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.enabled && len(b.servers) > 0
}

func (b *BootstrapResolver) getOrCreateHealth(id string) *bootstrapHealth {
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
	h = newBootstrapHealth()
	b.healthMap[id] = h
	return h
}

func (b *BootstrapResolver) getCached(host string) (string, bool) {
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

func (b *BootstrapResolver) putCached(host string, ip string) {
	b.cacheMu.Lock()
	b.cache[host] = &cachedBootstrapHost{
		ip:        ip,
		expiresAt: time.Now().Add(bsDefaultCacheTTL),
	}
	b.cacheMu.Unlock()
}

func (b *BootstrapResolver) choosePlan(servers []BootstrapServer, now time.Time) bootstrapPlan {
	if len(servers) == 0 {
		return bootstrapPlan{}
	}
	if len(servers) == 1 {
		return bootstrapPlan{primary: servers[0]}
	}

	scores := make([]bootstrapScore, len(servers))
	for i, entry := range servers {
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

	fallbacks := make([]BootstrapServer, len(remaining))
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

// ResolveHost 解析域名到 IP 字符串，遇到 IP 则直接返回
func (b *BootstrapResolver) ResolveHost(ctx context.Context, host string) (string, error) {
	if host == "" {
		return "", fmt.Errorf("empty host")
	}
	cleanHost := strings.Trim(host, "[]")
	if net.ParseIP(cleanHost) != nil {
		return cleanHost, nil
	}

	b.mu.RLock()
	enabled := b.enabled
	servers := make([]BootstrapServer, len(b.servers))
	copy(servers, b.servers)
	b.mu.RUnlock()

	if !enabled || len(servers) == 0 {
		return host, nil
	}

	normalizedHost := strings.ToLower(strings.TrimSpace(host))
	if cachedIP, ok := b.getCached(normalizedHost); ok {
		return cachedIP, nil
	}

	now := time.Now()
	plan := b.choosePlan(servers, now)
	if plan.primary.Address == "" {
		return "", fmt.Errorf("no bootstrap server configured")
	}

	executionList := append([]BootstrapServer{plan.primary}, plan.fallbacks...)
	var lastErr error

	for _, entry := range executionList {
		if ctx.Err() != nil {
			return "", ctx.Err()
		}

		stepCtx, stepCancel := context.WithTimeout(ctx, 1500*time.Millisecond)
		start := time.Now()
		resolvedIP, err := queryBootstrapDNS(stepCtx, entry.Address, normalizedHost)
		stepCancel()
		elapsedMs := time.Since(start).Milliseconds()
		if elapsedMs < 1 {
			elapsedMs = 1
		}

		health := b.getOrCreateHealth(entry.ID)
		isSuccess := (err == nil && resolvedIP != "")
		health.RecordResult(isSuccess, elapsedMs, time.Now())

		if isSuccess {
			b.putCached(normalizedHost, resolvedIP)
			return resolvedIP, nil
		}

		lastErr = err
	}

	if lastErr != nil {
		return "", fmt.Errorf("bootstrap resolution failed for %s: %w", host, lastErr)
	}
	return "", fmt.Errorf("all bootstrap servers failed for %s", host)
}

func queryBootstrapDNS(ctx context.Context, serverAddr, host string) (string, error) {
	return queryBootstrapDNSRecursive(ctx, serverAddr, host, 0)
}

func queryBootstrapDNSRecursive(ctx context.Context, serverAddr, host string, depth int) (string, error) {
	if depth > 3 {
		return "", fmt.Errorf("bootstrap cname loop limit exceeded for %s", host)
	}

	addr := serverAddr
	if _, _, err := net.SplitHostPort(addr); err != nil {
		addr = net.JoinHostPort(strings.Trim(addr, "[]"), "53")
	}

	client := &dns.Client{
		Net:     "udp",
		Timeout: 1500 * time.Millisecond,
		UDPSize: dns.MaxMsgSize,
	}

	// 优先查询 A 记录
	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(host), dns.TypeA)
	msg.RecursionDesired = true
	msg.Id = dns.Id()

	resp, _, err := client.ExchangeContext(ctx, msg, addr)
	if err == nil && resp != nil && resp.Truncated {
		tcpClient := &dns.Client{Net: "tcp", Timeout: 1500 * time.Millisecond}
		resp, _, err = tcpClient.ExchangeContext(ctx, msg, addr)
	}

	var cnameTarget string
	if err == nil && resp != nil {
		for _, rr := range resp.Answer {
			if a, ok := rr.(*dns.A); ok && a.A != nil {
				return a.A.String(), nil
			}
			if cn, ok := rr.(*dns.CNAME); ok && cn.Target != "" && cnameTarget == "" {
				cnameTarget = strings.TrimSuffix(cn.Target, ".")
			}
		}
	}

	// A 记录未返回则尝试 AAAA 记录
	msgAAAA := new(dns.Msg)
	msgAAAA.SetQuestion(dns.Fqdn(host), dns.TypeAAAA)
	msgAAAA.RecursionDesired = true
	msgAAAA.Id = dns.Id()

	respAAAA, _, errAAAA := client.ExchangeContext(ctx, msgAAAA, addr)
	if errAAAA == nil && respAAAA != nil && respAAAA.Truncated {
		tcpClient := &dns.Client{Net: "tcp", Timeout: 3 * time.Second}
		respAAAA, _, errAAAA = tcpClient.ExchangeContext(ctx, msgAAAA, addr)
	}

	if errAAAA == nil && respAAAA != nil {
		for _, rr := range respAAAA.Answer {
			if aaaa, ok := rr.(*dns.AAAA); ok && aaaa.AAAA != nil {
				return aaaa.AAAA.String(), nil
			}
			if cn, ok := rr.(*dns.CNAME); ok && cn.Target != "" && cnameTarget == "" {
				cnameTarget = strings.TrimSuffix(cn.Target, ".")
			}
		}
	}

	if cnameTarget != "" && !strings.EqualFold(cnameTarget, host) {
		return queryBootstrapDNSRecursive(ctx, serverAddr, cnameTarget, depth+1)
	}

	if err != nil {
		return "", fmt.Errorf("query bootstrap %s for %s: %w", addr, host, err)
	}
	return "", fmt.Errorf("no A/AAAA record for %s from %s", host, addr)
}
