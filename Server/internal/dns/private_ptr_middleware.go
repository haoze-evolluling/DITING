package dns

import (
	"net"
	"strconv"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// privateReverseSuffixes 定义 RFC 6303 与 RFC 7793 规定的私有与保留反向 DNS 权威解析区后缀
var privateReverseSuffixes = []string{
	// RFC 1918 私有 IPv4 地址块
	"10.in-addr.arpa",
	"168.192.in-addr.arpa",
	// 172.16.0.0/12 (172.16 ~ 172.31)
	"16.172.in-addr.arpa", "17.172.in-addr.arpa", "18.172.in-addr.arpa", "19.172.in-addr.arpa",
	"20.172.in-addr.arpa", "21.172.in-addr.arpa", "22.172.in-addr.arpa", "23.172.in-addr.arpa",
	"24.172.in-addr.arpa", "25.172.in-addr.arpa", "26.172.in-addr.arpa", "27.172.in-addr.arpa",
	"28.172.in-addr.arpa", "29.172.in-addr.arpa", "30.172.in-addr.arpa", "31.172.in-addr.arpa",

	// RFC 6598 / RFC 7793 运营商级 NAT (100.64.0.0/10: 100.64 ~ 100.127)
	"64.100.in-addr.arpa", "65.100.in-addr.arpa", "66.100.in-addr.arpa", "67.100.in-addr.arpa",
	"68.100.in-addr.arpa", "69.100.in-addr.arpa", "70.100.in-addr.arpa", "71.100.in-addr.arpa",
	"72.100.in-addr.arpa", "73.100.in-addr.arpa", "74.100.in-addr.arpa", "75.100.in-addr.arpa",
	"76.100.in-addr.arpa", "77.100.in-addr.arpa", "78.100.in-addr.arpa", "79.100.in-addr.arpa",
	"80.100.in-addr.arpa", "81.100.in-addr.arpa", "82.100.in-addr.arpa", "83.100.in-addr.arpa",
	"84.100.in-addr.arpa", "85.100.in-addr.arpa", "86.100.in-addr.arpa", "87.100.in-addr.arpa",
	"88.100.in-addr.arpa", "89.100.in-addr.arpa", "90.100.in-addr.arpa", "91.100.in-addr.arpa",
	"92.100.in-addr.arpa", "93.100.in-addr.arpa", "94.100.in-addr.arpa", "95.100.in-addr.arpa",
	"96.100.in-addr.arpa", "97.100.in-addr.arpa", "98.100.in-addr.arpa", "99.100.in-addr.arpa",
	"100.100.in-addr.arpa", "101.100.in-addr.arpa", "102.100.in-addr.arpa", "103.100.in-addr.arpa",
	"104.100.in-addr.arpa", "105.100.in-addr.arpa", "106.100.in-addr.arpa", "107.100.in-addr.arpa",
	"108.100.in-addr.arpa", "109.100.in-addr.arpa", "110.100.in-addr.arpa", "111.100.in-addr.arpa",
	"112.100.in-addr.arpa", "113.100.in-addr.arpa", "114.100.in-addr.arpa", "115.100.in-addr.arpa",
	"116.100.in-addr.arpa", "117.100.in-addr.arpa", "118.100.in-addr.arpa", "119.100.in-addr.arpa",
	"120.100.in-addr.arpa", "121.100.in-addr.arpa", "122.100.in-addr.arpa", "123.100.in-addr.arpa",
	"124.100.in-addr.arpa", "125.100.in-addr.arpa", "126.100.in-addr.arpa", "127.100.in-addr.arpa",

	// 链路本地 (RFC 3927 169.254.0.0/16)
	"254.169.in-addr.arpa",

	// 本地回环与未分配 (RFC 5735)
	"127.in-addr.arpa",
	"0.in-addr.arpa",
	"255.255.255.255.in-addr.arpa",

	// 测试网段 (TEST-NET-1/2/3)
	"2.0.192.in-addr.arpa",
	"100.51.198.in-addr.arpa",
	"113.0.203.in-addr.arpa",

	// IPv6 ULA (fc00::/7: c.f 与 d.f)
	"c.f.ip6.arpa",
	"d.f.ip6.arpa",

	// IPv6 链路本地 (fe80::/10: 8.e.f, 9.e.f, a.e.f, b.e.f)
	"8.e.f.ip6.arpa",
	"9.e.f.ip6.arpa",
	"a.e.f.ip6.arpa",
	"b.e.f.ip6.arpa",

	// IPv6 本地回环 (::1) 与未指定 (::)
	"1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa",
	"0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa",

	// 文档保留 (2001:db8::/32)
	"8.b.d.0.1.0.0.2.ip6.arpa",
}

// IsPrivateReverseZone 判定给定的域名是否属于 RFC 6303/7793 规定的私有保留反向解析区
func IsPrivateReverseZone(domain string) bool {
	clean := strings.ToLower(strings.Trim(domain, "."))
	for _, suffix := range privateReverseSuffixes {
		if clean == suffix || strings.HasSuffix(clean, "."+suffix) {
			return true
		}
	}
	return false
}

// PrivateReverseZoneApex 返回给定名称所属私有反向解析区的区顶点（含末尾点）。
//
// RFC 6303 §3 要求合成的否定应答以「区顶点」为 SOA 所有者名，而不是查询名本身：
// 对 1.2.168.192.in-addr.arpa 而言区顶点是 168.192.in-addr.arpa。用查询名当 SOA
// 所有者会让解析器误以为每个地址都是独立授权区，既破坏否定缓存（NXDOMAIN 无法
// 按区聚合），也不符合任何真实权威服务器的应答形态。
// 未命中任何私有后缀时返回空串。
func PrivateReverseZoneApex(domain string) string {
	clean := strings.ToLower(strings.Trim(domain, "."))
	best := ""
	for _, suffix := range privateReverseSuffixes {
		if clean != suffix && !strings.HasSuffix(clean, "."+suffix) {
			continue
		}
		// 取最长匹配：IPv6 的 ::1 等条目本身覆盖在更短的 ip6.arpa 条目之下
		if len(suffix) > len(best) {
			best = suffix
		}
	}
	if best == "" {
		return ""
	}
	return best + "."
}

// ParsePTRIP 将类似 "1.1.168.192.in-addr.arpa." 或 IPv6 nibble 格式还原解析为 net.IP
func ParsePTRIP(ptrName string) net.IP {
	clean := strings.ToLower(strings.Trim(ptrName, "."))
	if strings.HasSuffix(clean, ".in-addr.arpa") {
		labels := strings.Split(strings.TrimSuffix(clean, ".in-addr.arpa"), ".")
		if len(labels) == 4 {
			b0, err0 := strconv.ParseUint(labels[3], 10, 8)
			b1, err1 := strconv.ParseUint(labels[2], 10, 8)
			b2, err2 := strconv.ParseUint(labels[1], 10, 8)
			b3, err3 := strconv.ParseUint(labels[0], 10, 8)
			if err0 == nil && err1 == nil && err2 == nil && err3 == nil {
				return net.IPv4(byte(b0), byte(b1), byte(b2), byte(b3))
			}
		}
	} else if strings.HasSuffix(clean, ".ip6.arpa") {
		nibbles := strings.Split(strings.TrimSuffix(clean, ".ip6.arpa"), ".")
		if len(nibbles) == 32 {
			var ipBytes [16]byte
			for i := 0; i < 16; i++ {
				// RFC 3596: ip6.arpa 中的 nibbles 以逆序排列。
				// 对应字节 i (0~15) 的高 4 位位于索引 31-i*2，低 4 位位于索引 31-i*2-1
				msNibble, err1 := strconv.ParseUint(nibbles[31-i*2], 16, 8)
				lsNibble, err2 := strconv.ParseUint(nibbles[31-i*2-1], 16, 8)
				if err1 != nil || err2 != nil || msNibble > 0x0f || lsNibble > 0x0f {
					return nil
				}
				ipBytes[i] = byte(msNibble<<4 | lsNibble)
			}
			return net.IP(ipBytes[:])
		}
	}
	return nil
}

// NewPrivatePTRMiddleware 创建 RFC 6303 / RFC 7793 私有 PTR 反向解析防泄漏拦截中间件
// 深度借鉴自 dnscrypt-proxy (plugin_block_undelegated.go)、AdGuard Home (private_reverse_dns) 与 Pi-hole (bogus-priv)
// 若 Hosts、DNS Rewrite 等前置权威模块未命中对应私有 IP 反向记录，拦截并本地返回 NXDOMAIN，杜绝向公网上游泄露内部网络拓扑
func NewPrivatePTRMiddleware(enabledFunc func() bool, clientResolver *core.ClientResolver) Middleware {
	return func(ctx *DNSContext, next func() error) error {
		if ctx.Req == nil || len(ctx.Req.Question) == 0 {
			return next()
		}

		isEnabled := true
		if enabledFunc != nil {
			isEnabled = enabledFunc()
		}
		if !isEnabled {
			return next()
		}

		q := ctx.Req.Question[0]
		if q.Qtype != dns.TypePTR {
			return next()
		}

		if !IsPrivateReverseZone(q.Name) {
			return next()
		}

		// 若配置了客户端识别器，且识别器中已知该私有 IP 的主机名，则权威返回该主机名
		if clientResolver != nil {
			if ip := ParsePTRIP(q.Name); ip != nil {
				if hostName := clientResolver.IdentifyClient(ip); hostName != "" {
					ptrDomain := hostName
					if !strings.HasSuffix(ptrDomain, ".") {
						ptrDomain += "."
					}
					resp := new(dns.Msg)
					resp.SetReply(ctx.Req)
					resp.Authoritative = true
					resp.RecursionAvailable = true
					resp.Rcode = dns.RcodeSuccess
					resp.Answer = append(resp.Answer, &dns.PTR{
						Hdr: dns.RR_Header{
							Name:   q.Name,
							Rrtype: dns.TypePTR,
							Class:  dns.ClassINET,
							Ttl:    300,
						},
						Ptr: ptrDomain,
					})
					ctx.Resp = resp
					ctx.Set("source", "client_resolver_ptr")
					return nil
				}
			}
		}

		// 未命中任何本地权威映射：按 RFC 6303 §3 合成本地权威 NXDOMAIN 及 SOA 记录
		resp := new(dns.Msg)
		resp.SetReply(ctx.Req)
		resp.Authoritative = true
		resp.RecursionAvailable = true
		resp.Rcode = dns.RcodeNameError

		soaZone := PrivateReverseZoneApex(q.Name)
		if soaZone == "" {
			// 理论上不可达（上面刚判定过 IsPrivateReverseZone），兜底沿用查询名
			soaZone = q.Name
			if !strings.HasSuffix(soaZone, ".") {
				soaZone += "."
			}
		}
		resp.Ns = append(resp.Ns, &dns.SOA{
			Hdr: dns.RR_Header{
				Name:   soaZone,
				Rrtype: dns.TypeSOA,
				Class:  dns.ClassINET,
				Ttl:    300,
			},
			Ns:      "localhost.",
			Mbox:    "nobody.invalid.",
			Serial:  1,
			Refresh: 10000,
			Retry:   2400,
			Expire:  604800,
			Minttl:  300,
		})

		ctx.Resp = resp
		ctx.Set("source", "locally_served_zone")
		ctx.Set("private_ptr_blocked", true)
		return nil
	}
}
