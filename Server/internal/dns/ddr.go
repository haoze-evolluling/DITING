package dns

import (
	"net"
	"strings"

	"github.com/miekg/dns"
)

// ddrQueryName 是 DDR（RFC 9462）规定的探测名
const ddrQueryName = "_dns.resolver.arpa."

// ddrPriority 是所有 DDR 条目的优先级。
//
// 统一取 1：协议之间没有先后可言——选哪个由客户端的能力决定，
// 不是服务端能排的序。AdGuard Home 同样取 1。
const ddrPriority = 1

// DDRAnswer 描述一条要广播的加密解析入口。
//
// 与 EncryptedServerConfig 分开：那是监听器的运行形态，这里是「要告诉
// 客户端什么」。两者字段重合但生命周期不同——监听器可能绑定失败，
// 而广播出去的东西必须与真实在听的端口一致，因此由调用方逐项填。
type DDRAnswer struct {
	ServerName string
	// DoTEnabled / DoHEnabled / DoQEnabled 各自是否已在监听
	DoTEnabled bool
	DoHEnabled bool
	DoQEnabled bool
	DoTPort    int
	DoHPort    int
	DoQPort    int
	DoHPath    string
	// CertHasIPs 证书是否覆盖了 IP 地址。
	//
	// 只影响 DoT 是否广播：DoT 客户端从证书的 IP SAN 里取连接地址，
	// 证书不含 IP 时这些条目对它毫无用处，反而会让它认定服务器
	// 声明了一个自己无法使用的入口。
	CertHasIPs bool
}

// IsEmpty 报告是否没有任何可广播的入口。
func (a DDRAnswer) IsEmpty() bool {
	return !a.DoTEnabled && !a.DoHEnabled && !a.DoQEnabled
}

// BuildDDRResponse 按给定配置生成 DDR 应答。
//
// 只认 _dns.resolver.arpa. 的 SVCB 查询：DDR 规定用 SVCB 承载，
// 其余类型返回权威 NODATA——既说明「这里没有别的东西」，
// 也避免把探测泄漏给上游。
func BuildDDRResponse(req *dns.Msg, answer DDRAnswer) *dns.Msg {
	if req == nil || len(req.Question) == 0 {
		return nil
	}

	q := req.Question[0]
	resp := new(dns.Msg)
	resp.SetReply(req)
	resp.Authoritative = true
	resp.RecursionAvailable = true
	// SetReply 不复制 OPT，而 SVCB 仅在 EDNS(0) 下有意义：应答缺 OPT 会被
	// 合规客户端（RFC 6891 §6.2.1）当作「不支持 EDNS」而丢弃整条应答
	if opt := req.IsEdns0(); opt != nil {
		resp.SetEdns0(opt.UDPSize(), opt.Do())
	}

	if !strings.EqualFold(q.Name, ddrQueryName) || q.Qtype != dns.TypeSVCB {
		return resp
	}
	if answer.IsEmpty() {
		return resp
	}

	target := dns.Fqdn(strings.TrimSpace(answer.ServerName))
	if target == "." {
		// 没有服务器名就编不出合法的 Target：SVCB 的 TargetName 不允许
		// 为空，而写个占位域名等于把客户端引向别处。宁可不广播。
		return resp
	}

	if answer.DoHEnabled {
		resp.Answer = append(resp.Answer, buildDDRRecord(target, []dns.SVCBKeyValue{
			&dns.SVCBAlpn{Alpn: []string{"h2"}},
			&dns.SVCBPort{Port: clampPort(answer.DoHPort)},
			&dns.SVCBDoHPath{Template: ddrDoHPathTemplate(answer.DoHPath)},
		}))
	}

	if answer.DoTEnabled && answer.CertHasIPs {
		resp.Answer = append(resp.Answer, buildDDRRecord(target, []dns.SVCBKeyValue{
			&dns.SVCBAlpn{Alpn: []string{"dot"}},
			&dns.SVCBPort{Port: clampPort(answer.DoTPort)},
		}))
	}

	if answer.DoQEnabled {
		resp.Answer = append(resp.Answer, buildDDRRecord(target, []dns.SVCBKeyValue{
			&dns.SVCBAlpn{Alpn: []string{"doq"}},
			&dns.SVCBPort{Port: clampPort(answer.DoQPort)},
		}))
	}

	return resp
}

// buildDDRRecord 组装一条 SVCB 记录。
func buildDDRRecord(target string, values []dns.SVCBKeyValue) *dns.SVCB {
	return &dns.SVCB{
		Hdr: dns.RR_Header{
			Name:   ddrQueryName,
			Rrtype: dns.TypeSVCB,
			Class:  dns.ClassINET,
			Ttl:    600,
		},
		Priority: ddrPriority,
		Target:   target,
		Value:    values,
	}
}

// ddrDoHPathTemplate 把配置路径转成 DDR 的 dohpath 模板。
//
// RFC 9462 §4.2 规定模板里要带上待替换的查询占位符，客户端据此把
// DNS 报文拼进去；只写路径会让部分客户端得到 https://host/dns-query
// 这种缺参数的地址，进而请求失败。
func ddrDoHPathTemplate(path string) string {
	p := normalizeDoHPath(path)
	if strings.Contains(p, "{?dns}") {
		return p
	}
	return p + "{?dns}"
}

// clampPort 把端口压进 uint16。
//
// 越界值在配置层已被归一化，这里只是让「广播的端口」在任何情况下
// 都是一个能装进 SVCB 的数字。
func clampPort(port int) uint16 {
	if port <= 0 || port > 65535 {
		return 0
	}
	return uint16(port)
}

// ddrCertHasIPs 判断证书摘要是否覆盖了 IP 地址。
func ddrCertHasIPs(ips []string) bool {
	for _, s := range ips {
		if net.ParseIP(strings.TrimSpace(s)) != nil {
			return true
		}
	}
	return false
}
