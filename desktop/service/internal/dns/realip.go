package dns

import (
	"fmt"
	"net"
	"net/http"
	"strings"
)

// 反向代理透传头。按可信度顺序尝试：X-Forwarded-For 是事实标准，
// X-Real-IP 是 nginx 的惯用写法，两者都没有时再看自定义头。
const (
	headerXForwardedFor = "X-Forwarded-For"
	headerXRealIP       = "X-Real-IP"
)

// TrustedProxy 在「DoH 位于反向代理之后」的部署里还原真实客户端 IP。
//
// 存在的理由是安全而非便利：访问控制与限速都按客户端 IP 判定，
// 而转发头是调用方可以随便写的。若不加区分地采信，任何匿名客户端
// 只要加一个 `X-Forwarded-For: 127.0.0.1` 就能把自己伪装成白名单
// 成员，同时让限速对每台机器单独计数而失效。
//
// 因此这里的规则是「默认不信」：只有当直连对端本身落在可信列表里，
// 才去读转发头；否则全部忽略，一律以直连地址为准。
type TrustedProxy struct {
	ips    map[string]struct{}
	nets   []*net.IPNet
	header string
}

// NewTrustedProxy 解析可信来源列表。
//
// entries 支持单个 IP 与 CIDR 两种写法。enabled 为 false 时返回 nil，
// 调用方对 nil 接收者调用 RealClientIP 是安全的，一律得到直连地址——
// 把「未启用」表达成 nil 而不是一个空列表，是为了让默认路径上
// 连一次 map 查询都不发生。
func NewTrustedProxy(enabled bool, entries []string, header string) (*TrustedProxy, error) {
	if !enabled {
		return nil, nil
	}

	tp := &TrustedProxy{
		ips:    make(map[string]struct{}, len(entries)),
		header: strings.TrimSpace(header),
	}
	for _, raw := range entries {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		if strings.Contains(entry, "/") {
			_, ipNet, err := net.ParseCIDR(entry)
			if err != nil {
				return nil, fmt.Errorf("可信代理网段 %q 无效: %w", entry, err)
			}
			tp.nets = append(tp.nets, ipNet)
			continue
		}
		ip := net.ParseIP(entry)
		if ip == nil {
			return nil, fmt.Errorf("可信代理地址 %q 无效", entry)
		}
		// 统一按 v4 形式存：::ffff:1.2.3.4 与 1.2.3.4 必须命中同一条规则
		if v4 := ip.To4(); v4 != nil {
			ip = v4
		}
		tp.ips[ip.String()] = struct{}{}
	}
	return tp, nil
}

// Empty 报告可信列表是否为空。
//
// 空列表意味着「谁都不信」，与未启用等价，但它不会等价于关闭：
// 界面需要据此提示用户填了开关却没填地址。
func (t *TrustedProxy) Empty() bool {
	if t == nil {
		return true
	}
	return len(t.ips) == 0 && len(t.nets) == 0
}

// Trusts 判断某个 IP 是否在可信列表内
func (t *TrustedProxy) Trusts(ip net.IP) bool {
	if t == nil || ip == nil {
		return false
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	if _, ok := t.ips[ip.String()]; ok {
		return true
	}
	for _, n := range t.nets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// RealClientIP 还原真实客户端 IP。
//
// peer 是直连对端地址，header 是本次请求的头部。只有当 peer 可信时
// 才解析转发头，且解析出来的值不合法就退回 peer——转发头里塞一段
// 垃圾不该让这次查询失去来源，那会让限速把所有人算成同一个未知客户端。
func (t *TrustedProxy) RealClientIP(peer net.Addr, header http.Header) net.IP {
	peerIP := ipFromAddr(peer)
	if t == nil || peerIP == nil || !t.Trusts(peerIP) {
		return peerIP
	}

	if ip := t.ipFromCustomHeader(header); ip != nil {
		return ip
	}
	if ip := parseForwardedFor(header.Get(headerXForwardedFor), t); ip != nil {
		return ip
	}
	if ip := parseIPHeader(header.Get(headerXRealIP)); ip != nil {
		return ip
	}
	return peerIP
}

// ipFromCustomHeader 读取用户指定名字的转发头。
//
// 单独一个头部名而不是复用 XFF：Cloudflare、Fastly 这类服务用的是
// 各自命名的头，硬编码 XFF 会让这些部署下拿到的始终是代理自己的地址。
func (t *TrustedProxy) ipFromCustomHeader(header http.Header) net.IP {
	if t.header == "" || header == nil {
		return nil
	}
	// 自定义头的语义由填写者决定，可能承载整条链，故按 XFF 的规则解析
	if strings.EqualFold(t.header, headerXForwardedFor) {
		return parseForwardedFor(header.Get(t.header), t)
	}
	return parseIPHeader(header.Get(t.header))
}

// parseForwardedFor 从 X-Forwarded-For 里取出真实客户端 IP。
//
// 从右往左扫，取第一个不在可信列表里的地址。方向不能反：最左端是
// 客户端自己写进去的，直接采信等于把伪造权交给被识别的对象。
// 例如客户端 1.2.3.4 连上可信代理 P，随手写 `X-Forwarded-For: 9.9.9.9`，
// 代理追加后得到「9.9.9.9, 1.2.3.4」——从右往左第一个不可信的正是
// 真正的客户端 1.2.3.4。
//
// 整条链都在可信列表内时返回 nil，交给调用方回退到直连地址：
// 那种情况下没有任何一跳能代表终端。
func parseForwardedFor(value string, t *TrustedProxy) net.IP {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	for i := len(parts) - 1; i >= 0; i-- {
		ip := parseIPHeader(parts[i])
		if ip == nil {
			// 中途出现一段垃圾说明这条头已经不可信，整条作废比
			// 挑一段能解析的更安全
			return nil
		}
		if !t.Trusts(ip) {
			return ip
		}
	}
	return nil
}

// parseIPHeader 解析单个头部值里的 IP。
//
// 容忍三种常见写法：纯 IP、带端口的 IP、带方括号的 IPv6 字面量。
func parseIPHeader(value string) net.IP {
	s := strings.TrimSpace(value)
	if s == "" {
		return nil
	}
	s = strings.Trim(s, `"`)

	if ip := net.ParseIP(s); ip != nil {
		return normalizeIP(ip)
	}
	// 带端口或方括号的形式交给 SplitHostPort
	if host, _, err := net.SplitHostPort(s); err == nil {
		if ip := net.ParseIP(host); ip != nil {
			return normalizeIP(ip)
		}
	}
	return nil
}

// ipFromAddr 从网络地址里取出 IP
func ipFromAddr(addr net.Addr) net.IP {
	switch a := addr.(type) {
	case *net.TCPAddr:
		return normalizeIP(a.IP)
	case *net.UDPAddr:
		return normalizeIP(a.IP)
	}
	if addr == nil {
		return nil
	}
	if host, _, err := net.SplitHostPort(addr.String()); err == nil {
		return parseIPHeader(host)
	}
	return nil
}

// normalizeIP 把 IPv4-in-IPv6 折叠回 4 字节形式，
// 免得 ::ffff:1.2.3.4 与 1.2.3.4 被当成两个不同客户端
func normalizeIP(ip net.IP) net.IP {
	if ip == nil {
		return nil
	}
	if v4 := ip.To4(); v4 != nil {
		return v4
	}
	return ip
}

// doHClientAddr 取 DoH 请求的客户端地址，供访问控制与限速使用。
//
// 未配置可信代理时与 remoteAddrFromRequest 完全等价，不引入任何
// 行为变化——默认部署下 DoH 直接暴露，采信转发头只会带来伪造风险。
func (s *Server) doHClientAddr(r *http.Request) net.Addr {
	peer := remoteAddrFromRequest(r)

	s.mu.Lock()
	tp := (*TrustedProxy)(nil)
	if s.encrypted != nil {
		tp = s.encrypted.TrustedProxy
	}
	s.mu.Unlock()

	if tp == nil {
		return peer
	}
	ip := tp.RealClientIP(peer, r.Header)
	if ip == nil {
		return peer
	}
	// 端口取自直连对端：代理发起的连接端口与终端无关，仅作日志展示
	port := 0
	if ta, ok := peer.(*net.TCPAddr); ok {
		port = ta.Port
	}
	return &net.TCPAddr{IP: ip, Port: port}
}
