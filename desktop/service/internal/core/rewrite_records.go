package core

import (
	"encoding/base64"
	"fmt"
	"net"
	"strconv"
	"strings"

	"github.com/miekg/dns"
)

// RewriteRecord 描述一条自定义重写记录。
//
// 用于承载 RewriteRule 中 IPs/CNAME/TXT 三个快捷字段之外的记录类型
// （MX / SRV / NS / PTR / HTTPS / SVCB）。取值语法与 AdGuard Home 的
// $dnsrewrite 保持一致，便于用户在两处使用同一套写法：
//
//	MX     "32 example.mail"                优先级 空格 交换主机
//	SRV    "10 60 8080 example.com"         优先级 权重 端口 目标
//	NS     "ns1.example.com"
//	PTR    "host.example.com"
//	HTTPS  "32 example.com alpn=h3 ipv4hint=1.2.3.4"
//	SVCB   "1 . alpn=h3,h2 port=8443"
type RewriteRecord struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

// RewriteRCodeNone 表示未指定应答码覆盖，按 NOERROR 处理
const RewriteRCodeNone = ""

// rewriteRCodeNames 支持在重写规则中覆盖的应答码
var rewriteRCodeNames = map[string]int{
	"NOERROR":  dns.RcodeSuccess,
	"FORMERR":  dns.RcodeFormatError,
	"SERVFAIL": dns.RcodeServerFailure,
	"NXDOMAIN": dns.RcodeNameError,
	"NOTIMP":   dns.RcodeNotImplemented,
	"REFUSED":  dns.RcodeRefused,
}

// rewriteRecordTypes 支持在 RewriteRecord 中配置的记录类型
var rewriteRecordTypes = map[string]uint16{
	"A":     dns.TypeA,
	"AAAA":  dns.TypeAAAA,
	"CNAME": dns.TypeCNAME,
	"TXT":   dns.TypeTXT,
	"MX":    dns.TypeMX,
	"SRV":   dns.TypeSRV,
	"NS":    dns.TypeNS,
	"PTR":   dns.TypePTR,
	"HTTPS": dns.TypeHTTPS,
	"SVCB":  dns.TypeSVCB,
}

// svcbKeyByName 为 SVCB 参数名的查表；miekg/dns 只导出了 int → 名称方向。
//
// 名称取自 RFC 9460 §14.3.2 注册表，与 miekg/dns 内部映射保持一致。
var svcbKeyByName = map[string]dns.SVCBKey{
	"mandatory":       dns.SVCB_MANDATORY,
	"alpn":            dns.SVCB_ALPN,
	"no-default-alpn": dns.SVCB_NO_DEFAULT_ALPN,
	"port":            dns.SVCB_PORT,
	"ipv4hint":        dns.SVCB_IPV4HINT,
	"ech":             dns.SVCB_ECHCONFIG,
	"ipv6hint":        dns.SVCB_IPV6HINT,
	"dohpath":         dns.SVCB_DOHPATH,
	"ohttp":           dns.SVCB_OHTTP,
}

// RewriteRecordTypes 返回受支持的记录类型名（升序），供前端下拉与校验提示使用
func RewriteRecordTypes() []string {
	names := make([]string, 0, len(rewriteRecordTypes))
	for name := range rewriteRecordTypes {
		names = append(names, name)
	}
	// 固定顺序，避免前端下拉每次渲染时次序抖动
	sortStrings(names)
	return names
}

// sortStrings 对字符串切片做简单插入排序。
//
// 这里只有十余个元素，且仅在配置加载与前端取类型列表时调用，
// 引入 sort 包换来的收益不足以抵消一次额外依赖的心智负担。
func sortStrings(items []string) {
	for i := 1; i < len(items); i++ {
		for j := i; j > 0 && items[j] < items[j-1]; j-- {
			items[j], items[j-1] = items[j-1], items[j]
		}
	}
}

// ParseRewriteRCode 解析应答码名称，无法识别时返回 false
func ParseRewriteRCode(name string) (int, bool) {
	rcode, ok := rewriteRCodeNames[strings.ToUpper(strings.TrimSpace(name))]
	return rcode, ok
}

// buildRewriteRR 把一条 RewriteRecord 编译成应答记录。
//
// name 取自查询名而非规则里的域名，这样泛域名规则也能返回与查询相符的记录名。
// 返回 nil 表示该记录类型与查询类型不一致（调用方据此产出权威 NODATA）。
func buildRewriteRR(name string, qtype uint16, rec RewriteRecord, ttl uint32) (dns.RR, error) {
	rrtype, ok := rewriteRecordTypes[strings.ToUpper(strings.TrimSpace(rec.Type))]
	if !ok {
		return nil, fmt.Errorf("不支持的记录类型 %q", rec.Type)
	}

	// CNAME 是名字本身的属性，与请求的记录类型无关；其余类型仅在同类型查询时返回
	if rrtype != dns.TypeCNAME && rrtype != qtype {
		return nil, nil
	}

	header := dns.RR_Header{
		Name:   dns.Fqdn(name),
		Rrtype: rrtype,
		Class:  dns.ClassINET,
		Ttl:    ttl,
	}
	value := strings.TrimSpace(rec.Value)

	switch rrtype {
	case dns.TypeA:
		ip := net.ParseIP(value)
		if ip == nil || ip.To4() == nil {
			return nil, fmt.Errorf("A 记录的取值 %q 不是合法的 IPv4 地址", rec.Value)
		}
		return &dns.A{Hdr: header, A: ip.To4()}, nil

	case dns.TypeAAAA:
		ip := net.ParseIP(value)
		// To16() 对 IPv4 字面量也会返回 v4-mapped 地址（恒非 nil），
		// 单用它放行会合成 ::ffff:10.0.0.5 这种伪 AAAA；必须显式排除 IPv4。
		if ip == nil || ip.To4() != nil || ip.To16() == nil {
			return nil, fmt.Errorf("AAAA 记录的取值 %q 不是合法的 IPv6 地址", rec.Value)
		}
		return &dns.AAAA{Hdr: header, AAAA: ip.To16()}, nil

	case dns.TypeCNAME:
		if !isRewriteTarget(value) {
			return nil, fmt.Errorf("CNAME 记录的取值 %q 不是合法的域名", rec.Value)
		}
		return &dns.CNAME{Hdr: header, Target: dns.Fqdn(value)}, nil

	case dns.TypeNS:
		if !isRewriteTarget(value) {
			return nil, fmt.Errorf("NS 记录的取值 %q 不是合法的域名", rec.Value)
		}
		return &dns.NS{Hdr: header, Ns: dns.Fqdn(value)}, nil

	case dns.TypePTR:
		if !isRewriteTarget(value) {
			return nil, fmt.Errorf("PTR 记录的取值 %q 不是合法的域名", rec.Value)
		}
		return &dns.PTR{Hdr: header, Ptr: dns.Fqdn(value)}, nil

	case dns.TypeTXT:
		if value == "" {
			return nil, fmt.Errorf("TXT 记录缺少取值")
		}
		return &dns.TXT{Hdr: header, Txt: []string{value}}, nil

	case dns.TypeMX:
		fields := strings.Fields(value)
		if len(fields) != 2 {
			return nil, fmt.Errorf("MX 记录需要「优先级 交换主机」两个字段，得到 %q", rec.Value)
		}
		pref, err := parseUint16(fields[0])
		if err != nil {
			return nil, fmt.Errorf("MX 优先级无效: %w", err)
		}
		if !isRewriteTarget(fields[1]) {
			return nil, fmt.Errorf("MX 交换主机 %q 不是合法的域名", fields[1])
		}
		return &dns.MX{Hdr: header, Preference: pref, Mx: dns.Fqdn(fields[1])}, nil

	case dns.TypeSRV:
		fields := strings.Fields(value)
		if len(fields) != 4 {
			return nil, fmt.Errorf("SRV 记录需要「优先级 权重 端口 目标」四个字段，得到 %q", rec.Value)
		}
		priority, err := parseUint16(fields[0])
		if err != nil {
			return nil, fmt.Errorf("SRV 优先级无效: %w", err)
		}
		weight, err := parseUint16(fields[1])
		if err != nil {
			return nil, fmt.Errorf("SRV 权重无效: %w", err)
		}
		port, err := parseUint16(fields[2])
		if err != nil {
			return nil, fmt.Errorf("SRV 端口无效: %w", err)
		}
		if !isRewriteTarget(fields[3]) {
			return nil, fmt.Errorf("SRV 目标 %q 不是合法的域名", fields[3])
		}
		return &dns.SRV{
			Hdr:      header,
			Priority: priority,
			Weight:   weight,
			Port:     port,
			Target:   dns.Fqdn(fields[3]),
		}, nil

	case dns.TypeHTTPS, dns.TypeSVCB:
		return buildRewriteSVCB(header, value)
	}

	return nil, fmt.Errorf("记录类型 %q 暂未实现", rec.Type)
}

// buildRewriteSVCB 解析 "优先级 目标 [参数...]" 形式的 SVCB / HTTPS 取值
func buildRewriteSVCB(header dns.RR_Header, value string) (dns.RR, error) {
	fields := strings.Fields(value)
	if len(fields) < 2 {
		return nil, fmt.Errorf("SVCB/HTTPS 记录至少需要「优先级 目标」两个字段，得到 %q", value)
	}

	priority, err := parseUint16(fields[0])
	if err != nil {
		return nil, fmt.Errorf("SVCB 优先级无效: %w", err)
	}

	// 目标为 "." 表示「使用查询名本身」，是 SVCB 里最常见的写法
	target := strings.TrimSpace(fields[1])
	if target != "." && !isRewriteTarget(target) {
		return nil, fmt.Errorf("SVCB 目标 %q 不是合法的域名", fields[1])
	}
	if target != "." {
		target = dns.Fqdn(target)
	}

	params, err := ParseSVCBParams(fields[2:])
	if err != nil {
		return nil, err
	}

	svcb := dns.SVCB{Hdr: header, Priority: priority, Target: target, Value: params}
	if header.Rrtype == dns.TypeHTTPS {
		return &dns.HTTPS{SVCB: svcb}, nil
	}
	return &svcb, nil
}

// ParseSVCBParams 解析 SVCB / HTTPS 参数列表（各参数形如 key=value 或裸 key）。
//
// alpn 与 mandatory 本就接受逗号分隔的取值列表；ipv4hint / ipv6hint 则对齐
// AdGuard Home 的限制只接受单个地址（其解析器直接对整个取值调用 ParseIP，
// 多值会被自然拒绝），避免用户以为配了多个而实际只生效一个。
func ParseSVCBParams(params []string) ([]dns.SVCBKeyValue, error) {
	var out []dns.SVCBKeyValue
	seen := make(map[dns.SVCBKey]bool, len(params))

	for _, raw := range params {
		key, value, hasValue := strings.Cut(raw, "=")
		if hasValue {
			value = strings.Trim(value, `"`)
		}

		kv, k, err := buildSVCBParam(strings.ToLower(key), value, hasValue)
		if err != nil {
			return nil, err
		}
		if seen[k] {
			return nil, fmt.Errorf("SVCB 参数 %s 重复出现", key)
		}
		seen[k] = true
		out = append(out, kv)
	}
	return out, nil
}

// buildSVCBParam 构造单个 SVCB 参数
func buildSVCBParam(key, value string, hasValue bool) (dns.SVCBKeyValue, dns.SVCBKey, error) {
	switch key {
	case "alpn":
		alpn, err := splitSVCBList(value, hasValue, "alpn")
		if err != nil {
			return nil, 0, err
		}
		return &dns.SVCBAlpn{Alpn: alpn}, dns.SVCB_ALPN, nil

	case "port":
		port, err := parseUint16(value)
		if err != nil {
			return nil, 0, fmt.Errorf("port 参数无效: %w", err)
		}
		return &dns.SVCBPort{Port: port}, dns.SVCB_PORT, nil

	case "ipv4hint":
		hints, err := parseIPv4Hints(value)
		if err != nil {
			return nil, 0, err
		}
		return &dns.SVCBIPv4Hint{Hint: hints}, dns.SVCB_IPV4HINT, nil

	case "ipv6hint":
		hints, err := parseIPv6Hints(value)
		if err != nil {
			return nil, 0, err
		}
		return &dns.SVCBIPv6Hint{Hint: hints}, dns.SVCB_IPV6HINT, nil

	case "dohpath":
		if value == "" {
			return nil, 0, fmt.Errorf("dohpath 参数缺少取值")
		}
		return &dns.SVCBDoHPath{Template: value}, dns.SVCB_DOHPATH, nil

	case "ech":
		raw, err := base64.StdEncoding.DecodeString(value)
		if err != nil {
			return nil, 0, fmt.Errorf("ech 参数不是合法的 Base64 文本: %w", err)
		}
		return &dns.SVCBECHConfig{ECH: raw}, dns.SVCB_ECHCONFIG, nil

	case "no-default-alpn":
		return &dns.SVCBNoDefaultAlpn{}, dns.SVCB_NO_DEFAULT_ALPN, nil

	case "mandatory":
		names, err := splitSVCBList(value, hasValue, "mandatory")
		if err != nil {
			return nil, 0, err
		}
		codes := make([]dns.SVCBKey, 0, len(names))
		for _, name := range names {
			code, ok := svcbKeyByName[strings.ToLower(name)]
			if !ok {
				return nil, 0, fmt.Errorf("mandatory 参数引用了未知的键 %q", name)
			}
			codes = append(codes, code)
		}
		return &dns.SVCBMandatory{Code: codes}, dns.SVCB_MANDATORY, nil
	}

	return nil, 0, fmt.Errorf("不支持的 SVCB 参数 %q", key)
}

// splitSVCBList 拆分逗号分隔的取值，并拒绝空取值
func splitSVCBList(value string, hasValue bool, key string) ([]string, error) {
	if !hasValue || strings.TrimSpace(value) == "" {
		return nil, fmt.Errorf("%s 参数缺少取值", key)
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			return nil, fmt.Errorf("%s 参数含空取值", key)
		}
		out = append(out, p)
	}
	return out, nil
}

func parseIPv4Hints(value string) ([]net.IP, error) {
	hint := net.ParseIP(value)
	if hint == nil || hint.To4() == nil {
		return nil, fmt.Errorf("ipv4hint 参数 %q 不是合法的 IPv4 地址", value)
	}
	return []net.IP{hint.To4()}, nil
}

func parseIPv6Hints(value string) ([]net.IP, error) {
	hint := net.ParseIP(value)
	if hint == nil || hint.To16() == nil {
		return nil, fmt.Errorf("ipv6hint 参数 %q 不是合法的 IPv6 地址", value)
	}
	return []net.IP{hint.To16()}, nil
}

func parseUint16(value string) (uint16, error) {
	n, err := strconv.ParseUint(strings.TrimSpace(value), 10, 16)
	if err != nil {
		return 0, fmt.Errorf("%q 不是 0-65535 之间的整数", value)
	}
	return uint16(n), nil
}
