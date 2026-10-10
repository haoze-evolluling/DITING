package core

import (
	"context"
	"fmt"
	"math/rand"
	"net"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
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
		if h, portStr, err := net.SplitHostPort(addr); err == nil {
			host = h
			p, pErr := strconv.Atoi(portStr)
			if pErr != nil || p <= 0 || p > 65535 {
				return fmt.Errorf("bootstrap server %q: invalid port %q in address %q", s.ID, portStr, s.Address)
			}
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
		health := b.getOrCreateHealth(serverKey(entry, i))
		score := health.GetScore(entry, now)
		score.index = i
		scores[i] = score
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
		if s.index != primary.index {
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

	normalizedHost := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(cleanHost)), ".")
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

	for i, entry := range executionList {
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

		health := b.getOrCreateHealth(serverKey(entry, i))
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
