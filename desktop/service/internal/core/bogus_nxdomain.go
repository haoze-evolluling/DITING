package core

import (
	"fmt"
	"net"
	"strings"
	"sync/atomic"

	"github.com/miekg/dns"
)

// maxBogusNXDomainNetworks 限制伪应答地址条数上限。
//
// 每个应答都要与整份清单比对，无上限的清单会直接转化为无上限的响应延迟。
const maxBogusNXDomainNetworks = 256

// BogusNXDomainMatcher 判定应答中的 A/AAAA 是否落在"伪应答地址"集合内。
//
// 用途是纠正被劫持的解析结果：部分网络在域名不存在时并不返回 NXDOMAIN，
// 而是返回一个固定的"广告/导航页"地址并附上 NOERROR。客户端因此认为域名存在，
// 缓存与服务都会把这当成一次成功的解析。
//
// 条目同时接受单个 IP 与 CIDR 网段。
type BogusNXDomainMatcher struct {
	entries []string
	nets    []*net.IPNet
	exact   []net.IP
	hits    atomic.Uint64
}

// NewBogusNXDomainMatcher 解析伪应答地址清单；非法条目被剔除并汇总为错误。
//
// 返回的匹配器在任何情况下都可用：一条写错的地址不应让整项防护失效。
func NewBogusNXDomainMatcher(entries []string) (*BogusNXDomainMatcher, error) {
	m := &BogusNXDomainMatcher{}
	if len(entries) == 0 {
		return m, nil
	}

	var problems []string
	for _, raw := range entries {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		if len(m.entries) >= maxBogusNXDomainNetworks {
			problems = append(problems, fmt.Sprintf("伪应答地址超过上限 %d 条，其余已忽略", maxBogusNXDomainNetworks))
			break
		}

		if strings.Contains(entry, "/") {
			_, ipNet, err := net.ParseCIDR(entry)
			if err != nil {
				problems = append(problems, fmt.Sprintf("伪应答网段 %q 非法，已忽略: %v", entry, err))
				continue
			}
			m.nets = append(m.nets, ipNet)
			m.entries = append(m.entries, entry)
			continue
		}

		ip := net.ParseIP(entry)
		if ip == nil {
			problems = append(problems, fmt.Sprintf("伪应答地址 %q 非法，已忽略", entry))
			continue
		}
		m.exact = append(m.exact, ip)
		m.entries = append(m.entries, entry)
	}

	if len(problems) > 0 {
		return m, fmt.Errorf("%s", strings.Join(problems, "; "))
	}
	return m, nil
}

// MatchIP 判断单个地址是否命中伪应答集合
func (m *BogusNXDomainMatcher) MatchIP(ip net.IP) bool {
	if m == nil || ip == nil {
		return false
	}
	for _, candidate := range m.exact {
		if candidate.Equal(ip) {
			return true
		}
	}
	for _, ipNet := range m.nets {
		if ipNet.Contains(ip) {
			return true
		}
	}
	return false
}

// FindInMsg 扫描 Answer 节的 A/AAAA 记录，返回首个命中伪应答集合的地址。
//
// 只看 Answer 节：劫持是在"回答问题"的位置伪造结果，
// 而 Authority / Additional 里的地址属于辅助信息，据此改写应答会误伤正常解析。
func (m *BogusNXDomainMatcher) FindInMsg(msg *dns.Msg) (net.IP, bool) {
	if m == nil || msg == nil || len(m.entries) == 0 {
		return nil, false
	}
	for _, rr := range msg.Answer {
		var ip net.IP
		switch v := rr.(type) {
		case *dns.A:
			ip = v.A
		case *dns.AAAA:
			ip = v.AAAA
		default:
			continue
		}
		if m.MatchIP(ip) {
			m.hits.Add(1)
			return ip, true
		}
	}
	return nil, false
}

// Entries 返回当前生效的地址原文
func (m *BogusNXDomainMatcher) Entries() []string {
	if m == nil {
		return nil
	}
	return append([]string(nil), m.entries...)
}

// Size 返回已解析的条目条数
func (m *BogusNXDomainMatcher) Size() int {
	if m == nil {
		return 0
	}
	return len(m.entries)
}

// Hits 返回累计命中次数（被判定为伪应答的应答数）
func (m *BogusNXDomainMatcher) Hits() uint64 {
	if m == nil {
		return 0
	}
	return m.hits.Load()
}

// DefaultBogusNXDomainNetworks 返回一组"定义上不可能是有效应答"的地址，供前端作为初始值。
//
// 这里刻意只收 RFC 明确禁止出现在公开应答中的地址，不猜测具体运营商的劫持 IP——
// 后者因网络而异，硬编码只会造成误判。
func DefaultBogusNXDomainNetworks() []string {
	return []string{
		"0.0.0.0/8", // RFC 1122: 未指定地址，不得作为目的地址出现在应答中
		"::/128",    // IPv6 未指定地址
		"127.0.0.0/8", // RFC 1122: 环回地址不应由公开 DNS 返回
		"::1/128",     // IPv6 环回地址
	}
}
