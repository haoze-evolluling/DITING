package core

import (
	"log"
	"net"
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

// DNS64Synthesizer 实现 RFC 6052 与 RFC 6147 的 AAAA 记录合成引擎。
//
// 前缀解析、地址嵌入、排除集与“应答里是否已有有效 AAAA”都在 Rust 内核
// （rust/diting-dns64-core）里；这里只保留配置、锁，以及把内核回传的地址包成 dns.AAAA。
// 一个合成器对应一次配置：UpdateConfig 先建新内核实例、再在写锁内换指针并释放旧实例。
type DNS64Synthesizer struct {
	mu      sync.RWMutex
	enabled bool
	kernel  *dns64NativeEngine
}

// NewDNS64Synthesizer 创建 DNS64 合成引擎
//
// 前缀不合法返回 *dns64PrefixConfigError（调用方按配置错误处理，不阻断启动）；
// 内核缺失或不匹配返回普通错误，服务必须启动失败——没有降级的第二套实现。
func NewDNS64Synthesizer(cfg DNS64Config) (*DNS64Synthesizer, error) {
	kernel, err := buildDNS64NativeEngine(cfg.Enabled, cfg.Prefixes)
	if err != nil {
		return nil, err
	}
	return &DNS64Synthesizer{enabled: cfg.Enabled, kernel: kernel}, nil
}

// UpdateConfig 动态更新 DNS64 配置
func (s *DNS64Synthesizer) UpdateConfig(cfg DNS64Config) error {
	kernel, err := buildDNS64NativeEngine(cfg.Enabled, cfg.Prefixes)
	if err != nil {
		return err
	}

	s.mu.Lock()
	old := s.kernel
	s.enabled = cfg.Enabled
	s.kernel = kernel
	s.mu.Unlock()
	old.free()
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

// EmbedIPv4InIPv6 按照 RFC 6052 第 2.2 节将 IPv4 地址嵌入指定 IPv6 前缀中。
//
// 前缀按字节交给内核（`IPNet.IP.To16()` + 掩码长度），不走文本往返：`::ffff:0:0/96` 这类
// 折叠过的网段 `String()` 出来是 `0.0.0.0/0`，再解析就不是同一条前缀了。非 IPv6 掩码
// 与 RFC 6052 的 /32、/40、/48、/56、/64、/96 之外的长度都返回 nil。
func EmbedIPv4InIPv6(v4 net.IP, prefix *net.IPNet) net.IP {
	if prefix == nil {
		return nil
	}
	v4Bytes := v4.To4()
	if v4Bytes == nil {
		return nil
	}
	prefixIP := prefix.IP.To16()
	if prefixIP == nil {
		return nil
	}
	ones, bits := prefix.Mask.Size()
	if bits != net.IPv6len*8 {
		return nil
	}
	embedded, ok := embedIPv4InPrefix(prefixIP, ones, v4Bytes)
	if !ok {
		return nil
	}
	return net.IP(embedded)
}

// MapIPv4ToIPv6 按照 RFC 6052 第 2.2 节将 IPv4 地址映射为第一个配置前缀下的 IPv6 地址
func (s *DNS64Synthesizer) MapIPv4ToIPv6(v4 net.IP) net.IP {
	if s == nil {
		return nil
	}
	v4Bytes := v4.To4()
	if v4Bytes == nil {
		return nil
	}

	s.mu.RLock()
	defer s.mu.RUnlock()
	embedded, ok := s.kernel.embed(v4Bytes)
	if !ok {
		return nil
	}
	return net.IP(embedded)
}

// IsExcluded 判断 IPv6 地址是否在 RFC 6147 排除名单中
//
// 内核拒绝回答时按“已排除”处理：宁可不合成，也不合成出不该合成的地址。
func (s *DNS64Synthesizer) IsExcluded(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if s == nil {
		return true
	}

	s.mu.RLock()
	defer s.mu.RUnlock()
	excluded, err := s.kernel.excluded(ip)
	if err != nil {
		log.Printf("[DNS64] 排除集判定失败: %v（本次按已排除处理）\n", err)
		return true
	}
	return excluded
}

// HasValidAAAARecords 检查应答是否包含不在排除名单中的有效 AAAA 记录 (RFC 6147 Section 5.1.1 & 5.1.4)
func (s *DNS64Synthesizer) HasValidAAAARecords(msg *dns.Msg) bool {
	if msg == nil || len(msg.Answer) == 0 || s == nil {
		return false
	}

	// 地址为空（或 AAAA 记录里没有地址）是旧实现里 IsExcluded(nil) 的情形：不算有效 AAAA。
	addresses := make([][]byte, 0, len(msg.Answer))
	for _, rr := range msg.Answer {
		aaaa, ok := rr.(*dns.AAAA)
		if !ok || aaaa.AAAA == nil {
			continue
		}
		addresses = append(addresses, aaaa.AAAA)
	}
	if len(addresses) == 0 {
		return false
	}

	s.mu.RLock()
	defer s.mu.RUnlock()
	valid, err := s.kernel.hasValid(addresses)
	if err != nil {
		log.Printf("[DNS64] 有效 AAAA 判定失败: %v（本次按无有效 AAAA 处理）\n", err)
		return false
	}
	return valid
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
	defer s.mu.RUnlock()

	var res []*dns.AAAA
	for _, a := range aRecords {
		if a == nil || a.A == nil {
			continue
		}

		ttl := a.Hdr.Ttl
		if overrideTTL > 0 {
			ttl = overrideTTL
		}

		addresses, err := s.kernel.synthesize(a.A.To4())
		if err != nil {
			log.Printf("[DNS64] 合成 AAAA 失败: %v（跳过该条 A 记录）\n", err)
			continue
		}
		for _, address := range addresses {
			res = append(res, &dns.AAAA{
				Hdr: dns.RR_Header{
					Name:   a.Hdr.Name,
					Rrtype: dns.TypeAAAA,
					Class:  dns.ClassINET,
					Ttl:    ttl,
				},
				AAAA: net.IP(address),
			})
		}
	}
	return res
}
