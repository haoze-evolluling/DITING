package core

import (
	"fmt"
	"net"
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// WellKnownDNS64Prefix RFC 6052 规定的标准 DNS64 / NAT64 知名 IPv6 前缀
const WellKnownDNS64Prefix = "64:ff9b::/96"

// DNS64Config DNS64 IPv6-only 网络过渡合成配置。
// 借鉴自 blocky (dns64_resolver.go)、AdGuard Home (dns64.go) 与 Technitium DNS (RFC 6052 / RFC 6147)。
type DNS64Config struct {
	Enabled  bool     `json:"enabled"`  // 是否启用 DNS64 合成
	Prefixes []string `json:"prefixes"` // 用于合成 AAAA 记录的 IPv6 前缀列表（为空时默认使用 64:ff9b::/96）
}

// DefaultDNS64Config 返回默认 DNS64 配置
func DefaultDNS64Config() DNS64Config {
	return DNS64Config{
		Enabled:  false,
		Prefixes: []string{WellKnownDNS64Prefix},
	}
}

// DNS64Synthesizer 实现 RFC 6052 与 RFC 6147 的 AAAA 记录合成引擎
type DNS64Synthesizer struct {
	mu           sync.RWMutex
	enabled      bool
	prefixes     []*net.IPNet
	exclusionSet []*net.IPNet
}

// NewDNS64Synthesizer 创建 DNS64 合成引擎
func NewDNS64Synthesizer(cfg DNS64Config) (*DNS64Synthesizer, error) {
	s := &DNS64Synthesizer{
		enabled: cfg.Enabled,
	}

	// 初始化排除网段 (RFC 6147 Section 5.1.4: 避免回环、链路本地以及重复合成循环)
	defaultExclusions := []string{
		"::ffff:0:0/96", // IPv4-mapped
		"::1/128",       // Loopback
		"fe80::/10",     // Link-local
	}
	for _, excl := range defaultExclusions {
		_, ipNet, err := net.ParseCIDR(excl)
		if err == nil {
			s.exclusionSet = append(s.exclusionSet, ipNet)
		}
	}

	prefixes := cfg.Prefixes
	if len(prefixes) == 0 {
		prefixes = []string{WellKnownDNS64Prefix}
	}

	for _, p := range prefixes {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		_, ipNet, err := net.ParseCIDR(p)
		if err != nil {
			return nil, fmt.Errorf("解析 DNS64 前缀 %q 失败: %w", p, err)
		}
		// 校验前缀是否为 IPv6 且掩码支持 /96
		ones, bits := ipNet.Mask.Size()
		if bits != 128 || (ones != 32 && ones != 40 && ones != 48 && ones != 56 && ones != 64 && ones != 96) {
			return nil, fmt.Errorf("RFC 6052 规范仅支持 /32, /40, /48, /56, /64, /96 前缀长度，不支持 %s", p)
		}
		s.prefixes = append(s.prefixes, ipNet)
		// 按照 RFC 规范将配置的自身前缀加入排除集，防止多次级联递归合成
		s.exclusionSet = append(s.exclusionSet, ipNet)
	}

	return s, nil
}

// UpdateConfig 动态更新 DNS64 配置
func (s *DNS64Synthesizer) UpdateConfig(cfg DNS64Config) error {
	newSynth, err := NewDNS64Synthesizer(cfg)
	if err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.enabled = newSynth.enabled
	s.prefixes = newSynth.prefixes
	s.exclusionSet = newSynth.exclusionSet
	return nil
}

// IsEnabled 判断 DNS64 功能是否开启
func (s *DNS64Synthesizer) IsEnabled() bool {
	if s == nil {
		return false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.enabled
}

// EmbedIPv4InIPv6 按照 RFC 6052 第 2.2 节将 IPv4 地址嵌入指定 IPv6 前缀中
func EmbedIPv4InIPv6(v4 net.IP, prefix *net.IPNet) net.IP {
	v4Bytes := v4.To4()
	if v4Bytes == nil || prefix == nil {
		return nil
	}

	prefixIP := prefix.IP.To16()
	if prefixIP == nil {
		return nil
	}

	ones, bits := prefix.Mask.Size()
	if bits != 128 {
		return nil
	}

	v6 := make(net.IP, 16)
	copy(v6, prefixIP)

	switch ones {
	case 96:
		// bits 96-127 (bytes 12-15): Prefix(96) | IPv4(32)
		copy(v6[12:16], v4Bytes)
	case 64:
		// bits 72-103 (bytes 9-12): Prefix(64) | u(8) | IPv4(32) | Suffix(24)
		copy(v6[9:13], v4Bytes)
		v6[8] = 0 // 预留字节 u 必须为 0
	case 56:
		// bits 56-63 (byte 7) 与 72-95 (bytes 9-11): Prefix(56) | IPv4[0] | u(8) | IPv4[1-3] | Suffix(40)
		v6[7] = v4Bytes[0]
		copy(v6[9:12], v4Bytes[1:4])
		v6[8] = 0
	case 48:
		// bits 48-63 (bytes 6-7) 与 72-87 (bytes 9-10): Prefix(48) | IPv4[0-1] | u(8) | IPv4[2-3] | Suffix(56)
		copy(v6[6:8], v4Bytes[0:2])
		copy(v6[9:11], v4Bytes[2:4])
		v6[8] = 0
	case 40:
		// bits 40-63 (bytes 5-7) 与 72-79 (byte 9): Prefix(40) | IPv4[0-2] | u(8) | IPv4[3] | Suffix(48)
		copy(v6[5:8], v4Bytes[0:3])
		v6[9] = v4Bytes[3]
		v6[8] = 0
	case 32:
		// bits 32-63 (bytes 4-7): Prefix(32) | IPv4(32) | u(8) | Suffix(56)
		copy(v6[4:8], v4Bytes)
		v6[8] = 0
	default:
		return nil
	}

	return v6
}

// MapIPv4ToIPv6 按照 RFC 6052 第 2.2 节将 IPv4 地址映射为默认 IPv6 前缀
func (s *DNS64Synthesizer) MapIPv4ToIPv6(v4 net.IP) net.IP {
	v4 = v4.To4()
	if v4 == nil {
		return nil
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	var prefix *net.IPNet
	if len(s.prefixes) > 0 {
		prefix = s.prefixes[0]
	} else {
		_, prefix, _ = net.ParseCIDR(WellKnownDNS64Prefix)
	}

	return EmbedIPv4InIPv6(v4, prefix)
}

// IsExcluded 判断 IPv6 地址是否在 RFC 6147 排除名单中
func (s *DNS64Synthesizer) IsExcluded(ip net.IP) bool {
	if ip == nil {
		return true
	}
	s.mu.RLock()
	defer s.mu.RUnlock()

	if ip.IsUnspecified() {
		return true
	}

	for _, subnet := range s.exclusionSet {
		if subnet.Contains(ip) {
			return true
		}
	}
	return false
}

// HasValidAAAARecords 检查应答是否包含不在排除名单中的有效 AAAA 记录 (RFC 6147 Section 5.1.1 & 5.1.4)
func (s *DNS64Synthesizer) HasValidAAAARecords(msg *dns.Msg) bool {
	if msg == nil || len(msg.Answer) == 0 {
		return false
	}
	for _, rr := range msg.Answer {
		if aaaa, ok := rr.(*dns.AAAA); ok {
			if !s.IsExcluded(aaaa.AAAA) {
				return true
			}
		}
	}
	return false
}

// SynthesizeFromA 根据 A 记录切片合成 AAAA 记录列表（支持全部配置的前缀）
func (s *DNS64Synthesizer) SynthesizeFromA(aRecords []*dns.A) []*dns.AAAA {
	return s.SynthesizeFromAWithTTL(aRecords, 0)
}

// SynthesizeFromAWithTTL 根据 A 记录切片及指定 TTL 合成 AAAA 记录列表
func (s *DNS64Synthesizer) SynthesizeFromAWithTTL(aRecords []*dns.A, overrideTTL uint32) []*dns.AAAA {
	if !s.IsEnabled() || len(aRecords) == 0 {
		return nil
	}

	s.mu.RLock()
	prefixes := s.prefixes
	if len(prefixes) == 0 {
		_, defaultNet, _ := net.ParseCIDR(WellKnownDNS64Prefix)
		prefixes = []*net.IPNet{defaultNet}
	}
	s.mu.RUnlock()

	var res []*dns.AAAA
	for _, a := range aRecords {
		if a == nil || a.A == nil {
			continue
		}

		ttl := a.Hdr.Ttl
		if overrideTTL > 0 {
			ttl = overrideTTL
		}

		for _, pfx := range prefixes {
			v6 := EmbedIPv4InIPv6(a.A, pfx)
			if v6 == nil {
				continue
			}
			aaaa := &dns.AAAA{
				Hdr: dns.RR_Header{
					Name:   a.Hdr.Name,
					Rrtype: dns.TypeAAAA,
					Class:  dns.ClassINET,
					Ttl:    ttl,
				},
				AAAA: v6,
			}
			res = append(res, aaaa)
		}
	}
	return res
}
