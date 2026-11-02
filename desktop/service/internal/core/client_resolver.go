package core

import (
	"context"
	"net"
	"strings"
	"sync"
	"time"
)

// ClientAlias 静态绑定的客户端友好名称映射
type ClientAlias struct {
	IP   string `json:"ip"`   // 客户端 IP (IPv4 或 IPv6)
	Name string `json:"name"` // 友好主机名，例如 "Work-Laptop"
}

// ClientInfo 客户端运行态识别与统计信息
type ClientInfo struct {
	IP         string `json:"ip"`
	Name       string `json:"name"`
	QueryCount uint64 `json:"queryCount"`
	LastSeen   int64  `json:"lastSeen"` // Unix 秒
}

// ClientConfig 客户端识别与主机名解析配置
type ClientConfig struct {
	Enabled    bool          `json:"enabled"`    // 是否启用客户端识别
	EnableRDNS bool          `json:"enableRDNS"` // 是否启用局域网反向 DNS (rDNS) 自动发现主机名
	CacheTTL   time.Duration `json:"cacheTTL"`   // 主机名缓存生存时长，默认 1 小时
	Aliases    []ClientAlias `json:"aliases"`    // 静态别名列表

	// 客户端分组与分组级精细策略
	GroupsEnabled bool          `json:"groupsEnabled"`
	Groups        []ClientGroup `json:"groups"`
}

// DefaultClientConfig 默认客户端配置
func DefaultClientConfig() ClientConfig {
	return ClientConfig{
		Enabled:    true,
		EnableRDNS: true,
		CacheTTL:   time.Hour,
		Aliases:    []ClientAlias{},
		Groups:     []ClientGroup{},
	}
}

type cachedNameEntry struct {
	name      string
	expiresAt time.Time
}

// ReverseLookuper 本地内存逆向 PTR 查询接口
type ReverseLookuper interface {
	LookupReverse(ip net.IP) string
}

const (
	maxConcurrentRDNS = 16
	maxClientStats    = 4096
	maxClientCache    = 4096
)

// ClientResolver 客户端主机名识别与活动跟踪器
// 深度借鉴自 Blocky (client_names_resolver.go) 与 AdGuard Home (internal/rdns)
type ClientResolver struct {
	mu         sync.RWMutex
	enabled    bool
	enableRDNS bool
	cacheTTL   time.Duration
	aliases    map[string]string          // ipStr -> name
	cache      map[string]cachedNameEntry // ipStr -> cache
	stats      map[string]*ClientInfo     // ipStr -> info
	inFlight   map[string]bool            // 防止对同一未命中 IP 发起并发重复 rDNS 查找
	sem        chan struct{}              // 限制并发后台 rDNS 数量，抵御高并发探测与资源耗尽
	lookupers  []ReverseLookuper
	lookupAddr func(ctx context.Context, addr string) ([]string, error) // 可插拔底层反向解析函数
}

// NewClientResolver 创建客户端主机名识别器
func NewClientResolver(cfg ClientConfig, lookupers ...ReverseLookuper) *ClientResolver {
	ttl := cfg.CacheTTL
	if ttl <= 0 {
		ttl = time.Hour
	}
	r := &ClientResolver{
		enabled:    cfg.Enabled,
		enableRDNS: cfg.EnableRDNS,
		cacheTTL:   ttl,
		aliases:    make(map[string]string),
		cache:      make(map[string]cachedNameEntry),
		stats:      make(map[string]*ClientInfo),
		inFlight:   make(map[string]bool),
		sem:        make(chan struct{}, maxConcurrentRDNS),
		lookupers:  lookupers,
		lookupAddr: func(ctx context.Context, addr string) ([]string, error) {
			var resolver net.Resolver
			return resolver.LookupAddr(ctx, addr)
		},
	}
	for _, alias := range cfg.Aliases {
		ip := strings.TrimSpace(alias.IP)
		name := strings.TrimSpace(alias.Name)
		if ip != "" && name != "" {
			if parsed := net.ParseIP(ip); parsed != nil {
				if v4 := parsed.To4(); v4 != nil {
					ip = v4.String()
				}
			}
			r.aliases[ip] = name
		}
	}
	return r
}

// IdentifyClient 根据客户端 IP 解析友好名称并更新活跃统计
func (r *ClientResolver) IdentifyClient(ip net.IP) string {
	if ip == nil {
		return ""
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	ipStr := ip.String()

	// 1. 记录或累加请求指标
	r.mu.Lock()
	info, exists := r.stats[ipStr]
	if !exists {
		// 内存容量淘汰保护
		if len(r.stats) >= maxClientStats {
			for k := range r.stats {
				if _, hasAlias := r.aliases[k]; !hasAlias {
					delete(r.stats, k)
					break
				}
			}
		}
		info = &ClientInfo{
			IP:       ipStr,
			LastSeen: time.Now().Unix(),
		}
		r.stats[ipStr] = info
	}
	info.QueryCount++
	info.LastSeen = time.Now().Unix()
	r.mu.Unlock()

	if !r.enabled {
		return ""
	}

	// 2. 检查静态配置的别名
	r.mu.RLock()
	alias, hasAlias := r.aliases[ipStr]
	r.mu.RUnlock()
	if hasAlias {
		r.updateInfoName(ipStr, alias)
		return alias
	}

	// 3. 回环地址直接识别为 localhost
	if ip.IsLoopback() {
		r.updateInfoName(ipStr, "localhost")
		return "localhost"
	}

	// 4. 检查内存本地 reverseLookuper (如 Hosts 或自定义 Rewrite PTR)
	for _, lookuper := range r.lookupers {
		if lookuper != nil {
			if name := lookuper.LookupReverse(ip); name != "" {
				r.updateInfoName(ipStr, name)
				return name
			}
		}
	}

	// 5. 检查缓存
	now := time.Now()
	r.mu.RLock()
	entry, hasCached := r.cache[ipStr]
	r.mu.RUnlock()
	if hasCached && entry.expiresAt.After(now) {
		if entry.name != "" {
			r.updateInfoName(ipStr, entry.name)
		}
		return entry.name
	}

	// 6. 若启用了 rDNS 且当前未在查找中，带并发限制启动异步后台解析
	if r.enableRDNS {
		r.mu.Lock()
		inProgress := r.inFlight[ipStr]
		if !inProgress {
			select {
			case r.sem <- struct{}{}:
				r.inFlight[ipStr] = true
				go func(targetIP string) {
					defer func() { <-r.sem }()
					r.asyncResolveRDNS(targetIP)
				}(ipStr)
			default:
				// 并发已达上限，跳过本次解析以保护系统
			}
		}
		r.mu.Unlock()
	}

	// 若缓存中存在过期条目，暂时降级返回旧名称
	if hasCached && entry.name != "" {
		return entry.name
	}
	return ""
}

func (r *ClientResolver) asyncResolveRDNS(ipStr string) {
	defer func() {
		r.mu.Lock()
		delete(r.inFlight, ipStr)
		r.mu.Unlock()
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	names, err := r.lookupAddr(ctx, ipStr)
	resolvedName := ""
	if err == nil && len(names) > 0 {
		// 取第一个有效反向主机名，去除末尾点号
		resolvedName = strings.TrimSuffix(names[0], ".")
	}

	ttl := r.cacheTTL
	if resolvedName == "" {
		// 负缓存（反查失败）采用较短过期时间，以便网络恢复后重新发现
		if ttl > 5*time.Minute {
			ttl = 5 * time.Minute
		}
	}

	r.mu.Lock()
	if len(r.cache) >= maxClientCache {
		now := time.Now()
		for k, v := range r.cache {
			if v.expiresAt.Before(now) {
				delete(r.cache, k)
				break
			}
		}
		if len(r.cache) >= maxClientCache {
			for k := range r.cache {
				delete(r.cache, k)
				break
			}
		}
	}
	r.cache[ipStr] = cachedNameEntry{
		name:      resolvedName,
		expiresAt: time.Now().Add(ttl),
	}
	if resolvedName != "" {
		if info, ok := r.stats[ipStr]; ok {
			info.Name = resolvedName
		}
	}
	r.mu.Unlock()
}

func (r *ClientResolver) updateInfoName(ipStr, name string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if info, ok := r.stats[ipStr]; ok {
		info.Name = name
	}
}

// SetAlias 设置或更新客户端静态别名
func (r *ClientResolver) SetAlias(ip, name string) {
	ipStr := strings.TrimSpace(ip)
	nameStr := strings.TrimSpace(name)
	if ipStr == "" {
		return
	}
	if parsed := net.ParseIP(ipStr); parsed != nil {
		if v4 := parsed.To4(); v4 != nil {
			ipStr = v4.String()
		}
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if nameStr == "" {
		delete(r.aliases, ipStr)
	} else {
		r.aliases[ipStr] = nameStr
		if info, ok := r.stats[ipStr]; ok {
			info.Name = nameStr
		}
	}
}

// GetClients 获取所有已识别及已配置别名的客户端信息
func (r *ClientResolver) GetClients() []ClientInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()

	seen := make(map[string]bool)
	result := make([]ClientInfo, 0, len(r.stats)+len(r.aliases))
	for _, info := range r.stats {
		item := *info
		if item.Name == "" {
			if alias, ok := r.aliases[item.IP]; ok {
				item.Name = alias
			}
		}
		seen[item.IP] = true
		result = append(result, item)
	}

	for ip, alias := range r.aliases {
		if !seen[ip] {
			result = append(result, ClientInfo{
				IP:         ip,
				Name:       alias,
				QueryCount: 0,
				LastSeen:   0,
			})
		}
	}
	return result
}

// Configure 动态重配客户端识别器
func (r *ClientResolver) Configure(cfg ClientConfig) {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.enabled = cfg.Enabled
	r.enableRDNS = cfg.EnableRDNS
	if cfg.CacheTTL > 0 {
		r.cacheTTL = cfg.CacheTTL
	}
	r.aliases = make(map[string]string)
	for _, alias := range cfg.Aliases {
		ip := strings.TrimSpace(alias.IP)
		name := strings.TrimSpace(alias.Name)
		if ip != "" && name != "" {
			if parsed := net.ParseIP(ip); parsed != nil {
				if v4 := parsed.To4(); v4 != nil {
					ip = v4.String()
				}
			}
			r.aliases[ip] = name
		}
	}
}
