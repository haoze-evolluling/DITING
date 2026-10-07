package core

import (
	"fmt"
	"strings"
	"time"

	"github.com/miekg/dns"
)

// NormalizeCacheConfig 规范化缓存配置并补全非法/缺失参数
func NormalizeCacheConfig(cfg *CacheConfig) {
	if cfg.MaxEntries <= 0 {
		cfg.MaxEntries = DefaultMaxCacheEntries
	}
	if cfg.MaxTTLSeconds <= 0 {
		cfg.MaxTTLSeconds = 3600
	}
	if cfg.FixedTTLSeconds <= 0 {
		cfg.FixedTTLSeconds = 3600
	}
	if cfg.MinTTLSeconds <= 0 {
		cfg.MinTTLSeconds = 60
	}
	if cfg.StaleFallbackSeconds <= 0 {
		cfg.StaleFallbackSeconds = 300
	}
	if cfg.NegativeTTLSeconds <= 0 {
		cfg.NegativeTTLSeconds = 30
	}
	if cfg.Mode == "" {
		cfg.Mode = "limit_max_ttl"
	}
}

// CacheKey 生成标准化缓存键 (domain:qtype:qclass)
func CacheKey(domain string, qtype, qclass uint16) string {
	normalized := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(domain), "."))
	return fmt.Sprintf("%s:%d:%d", normalized, qtype, qclass)
}

// fnv32 计算 FNV-1a 哈希用于分片路由
func fnv32(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

// ExtractMinTTL 提取 DNS 报文中的最小生效 TTL (RFC 2181 / RFC 2308)
func ExtractMinTTL(msg *dns.Msg) (uint32, bool) {
	if msg == nil {
		return 0, false
	}

	var minTTL uint32
	found := false

	// RFC 2181 §5.2: 应答节 Answer 控制成功响应的 TTL
	if len(msg.Answer) > 0 {
		for _, rr := range msg.Answer {
			if rr == nil || rr.Header() == nil || rr.Header().Rrtype == dns.TypeOPT {
				continue
			}
			ttl := rr.Header().Ttl
			if !found || ttl < minTTL {
				minTTL = ttl
				found = true
			}
		}
		if found {
			return minTTL, true
		}
	}

	// 负缓存 (NODATA 或 NXDOMAIN, RFC 2308): 提取 Authority 节中 SOA 记录的 MINTTL 或 TTL
	for _, rr := range msg.Ns {
		if soa, ok := rr.(*dns.SOA); ok && soa.Header() != nil {
			ttl := soa.Minttl
			if ttl == 0 || (soa.Header().Ttl > 0 && soa.Header().Ttl < ttl) {
				ttl = soa.Header().Ttl
			}
			return ttl, true
		}
	}

	return 0, false
}

// CalculateEffectiveTTL 根据上游 TTL 与策略模式计算正向缓存的有效时长
func CalculateEffectiveTTL(upstreamTTL uint32, cfg CacheConfig) time.Duration {
	ttl := int64(upstreamTTL)
	switch strings.ToLower(cfg.Mode) {
	case "follow_dns_ttl":
		// 跟随上游 TTL，不做上限裁剪
	case "fixed_ttl":
		if cfg.FixedTTLSeconds > 0 {
			ttl = cfg.FixedTTLSeconds
		}
	case "limit_max_ttl":
		fallthrough
	default:
		if cfg.MaxTTLSeconds > 0 && ttl > cfg.MaxTTLSeconds {
			ttl = cfg.MaxTTLSeconds
		}
	}

	if strings.ToLower(cfg.Mode) != "fixed_ttl" && cfg.MinTTLEnabled && cfg.MinTTLSeconds > 0 {
		if ttl < cfg.MinTTLSeconds {
			ttl = cfg.MinTTLSeconds
		}
	}

	if ttl <= 0 {
		return 0
	}
	return time.Duration(ttl) * time.Second
}

// CalculateNegativeTTL 计算负缓存 (NXDOMAIN / NODATA) 的有效时长 (RFC 2308)
func CalculateNegativeTTL(soaTTL uint32, found bool, cfg CacheConfig) time.Duration {
	negTTL := int64(soaTTL)
	if !found || negTTL <= 0 || (cfg.NegativeTTLSeconds > 0 && negTTL > cfg.NegativeTTLSeconds) {
		negTTL = cfg.NegativeTTLSeconds
	}
	if negTTL <= 0 {
		negTTL = 30
	}
	// 安全上下限防御 (5s ~ 300s)
	if negTTL < 5 {
		negTTL = 5
	}
	if negTTL > 300 {
		negTTL = 300
	}
	return time.Duration(negTTL) * time.Second
}

// RewriteTTL 重写 DNS 报文所有记录的 TTL 为指定值 (RFC 规范剩余递减生存期)
func RewriteTTL(msg *dns.Msg, ttl uint32) {
	if msg == nil {
		return
	}
	for _, rr := range msg.Answer {
		if rr != nil && rr.Header() != nil && rr.Header().Rrtype != dns.TypeOPT {
			rr.Header().Ttl = ttl
		}
	}
	for _, rr := range msg.Ns {
		if rr != nil && rr.Header() != nil && rr.Header().Rrtype != dns.TypeOPT {
			rr.Header().Ttl = ttl
		}
	}
	for _, rr := range msg.Extra {
		if rr != nil && rr.Header() != nil && rr.Header().Rrtype != dns.TypeOPT {
			rr.Header().Ttl = ttl
		}
	}
}

// ExtractIPs 从 DNS 响应 Answer 节中提取 A / AAAA IP 字符串列表
func ExtractIPs(msg *dns.Msg) []string {
	if msg == nil || len(msg.Answer) == 0 {
		return nil
	}
	var ips []string
	seen := make(map[string]struct{})
	for _, ans := range msg.Answer {
		var ipStr string
		switch r := ans.(type) {
		case *dns.A:
			if r.A != nil {
				ipStr = r.A.String()
			}
		case *dns.AAAA:
			if r.AAAA != nil {
				ipStr = r.AAAA.String()
			}
		}
		if ipStr != "" {
			if _, exists := seen[ipStr]; !exists {
				seen[ipStr] = struct{}{}
				ips = append(ips, ipStr)
			}
		}
	}
	return ips
}
