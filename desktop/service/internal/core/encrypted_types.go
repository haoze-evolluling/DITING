package core

import (
	"crypto/x509"
	"fmt"
	"net"
	"strconv"
	"strings"
)

// 加密 DNS 服务端监听器的默认端口与路径。
//
// 853 与 443 是 RFC 7858 / RFC 8484 的注册端口，也是客户端
// （systemd-resolved、Chrome、iOS 配置描述文件）默认尝试的端口，
// 不按约定使用会让「粘贴一个地址就能用」这件事失效。
const (
	DefaultDoTPort = 853
	DefaultDoHPort = 443
	DefaultDoQPort = 853
	DefaultDoHPath = "/dns-query"
	DefaultServerName = "dns.lan"
)

// 服务端证书的来源。
const (
	// CertSourceSelfSigned 服务自签（首次启动时生成，写证书目录）
	CertSourceSelfSigned = "self_signed"
	// CertSourceFile 从宿主机上的 PEM 文件读取
	CertSourceFile = "file"
	// CertSourcePKCS12 从宿主机上的 PKCS#12 文件读取
	CertSourcePKCS12 = "pkcs12"
)

// CertConfig 加密 DNS 服务端证书配置。
//
// 这只是配置，不含任何私钥材料：私钥始终留在磁盘上由 CertManager 按需读取，
// 既不进配置文件也不经 IPC 回传。证书链与私钥一旦进入配置对象，
// 它就会随 /api/v1/status 之类的只读接口扩散到控制台与日志里。
type CertConfig struct {
	// Source 证书来源，取值见 CertSource* 常量
	Source string `json:"source"`
	// CertFile 证书链 PEM 路径（Source 为 file 或 pkcs12 时使用）
	CertFile string `json:"certFile"`
	// KeyFile 私钥 PEM 路径（Source 为 file 时使用）
	KeyFile string `json:"keyFile"`
	// PKCS12Password PKCS#12 文件口令（Source 为 pkcs12 时使用）
	PKCS12Password string `json:"pkcs12Password"`
	// KeyType 自签密钥类型；空值与 "ecdsa" 同义，另一取值为 "rsa"
	KeyType string `json:"keyType"`
	// CommonName 自签证书的 CN
	CommonName string `json:"commonName"`
	// DNSNames 自签证书的 SAN 域名列表
	DNSNames []string `json:"dnsNames"`
	// IPAddresses 自签证书的 SAN IP 列表
	IPAddresses []string `json:"ipAddresses"`
	// ValidDays 自签证书有效期（天）
	ValidDays int `json:"validDays"`
}

// EncryptedDNSConfig 加密 DNS 服务端配置。
//
// 三个监听器各自独立开关：只开 DoT 是常见形态（移动端原生支持最好），
// 强制要求全开才能用会把这个功能挡在门外。本批次只落配置与证书，
// 监听器在后续步骤挂载。
type EncryptedDNSConfig struct {
	Enabled bool       `json:"enabled"`
	Cert    CertConfig `json:"cert"`

	// DoTEnabled / DoHEnabled / DoQEnabled 各监听器开关
	DoTEnabled bool `json:"dotEnabled"`
	DoHEnabled bool `json:"dohEnabled"`
	DoQEnabled bool `json:"doqEnabled"`

	// ListenAddress 加密监听器的绑定地址；空值表示全部网卡
	ListenAddress string `json:"listenAddress"`

	DoTPort int    `json:"dotPort"`
	DoHPort int    `json:"dohPort"`
	DoQPort int    `json:"doqPort"`
	DoHPath string `json:"dohPath"`

	// ServerName 客户端应使用的服务器名，用于生成 DDR 广播与移动端描述文件
	ServerName string `json:"serverName"`

	// DDREnabled 是否应答 _dns.resolver.arpa. 的 SVCB 探测（RFC 9462）。
	//
	// 默认关闭：DDR 会让客户端自动切到本机做加密解析，一旦证书不被
	// 信任，客户端会直接失去解析能力——比起手动少填一个地址，
	// 这个代价大得多。
	DDREnabled bool `json:"ddrEnabled"`

	// UUID 移动端配置描述文件的标识；首次生成后固定，避免设备重复安装
	UUID string `json:"uuid"`

	// ReverseProxy 反向代理透传配置。
	//
	// 默认关闭：开启意味着采信请求里可被伪造的转发头，只有在 DoH
	// 确实位于自己掌握的反向代理之后时才该打开。
	ReverseProxy ReverseProxyConfig `json:"reverseProxy"`
}

// ReverseProxyConfig 反向代理可信来源配置。
//
// 列表为空与 Enabled 为 false 等价（谁都不信），保留两个字段是因为
// 用户可能想先填好地址、确认无误后再打开开关。
type ReverseProxyConfig struct {
	Enabled bool `json:"enabled"`
	// TrustedSources 可信代理的 IP 或 CIDR 列表
	TrustedSources []string `json:"trustedSources"`
	// ClientIPHeader 自定义转发头名；留空时依次尝试
	// X-Forwarded-For 与 X-Real-IP。Cloudflare 之类用自有头名的
	// 部署必须填写，否则拿到的始终是代理自己的地址。
	ClientIPHeader string `json:"clientIpHeader"`
}

// DefaultEncryptedDNSConfig 返回默认配置（默认全部关闭）。
//
// 默认关闭是刻意的：开启需要在宿主机上占用 443/853 这类特权端口，
// 且客户端一旦指向一个证书不受信任的服务器，会直接失去解析能力。
func DefaultEncryptedDNSConfig() EncryptedDNSConfig {
	return EncryptedDNSConfig{
		Enabled:       false,
		Cert:          DefaultCertConfig(),
		DoTEnabled:    false,
		DoHEnabled:    false,
		DoQEnabled:    false,
		ListenAddress: "",
		DoTPort:       DefaultDoTPort,
		DoHPort:       DefaultDoHPort,
		DoQPort:       DefaultDoQPort,
		DoHPath:       DefaultDoHPath,
		ServerName:    DefaultServerName,
	}
}

// DefaultCertConfig 返回默认证书配置（自签 ECDSA P-256）
//
// 默认选 ECDSA 而非 RSA：握手更快、密钥更小，而 P-256 的安全性对
// DNS 场景绰绰有余。要求 RSA 的场景（老客户端）可在界面上切换。
func DefaultCertConfig() CertConfig {
	return CertConfig{
		Source:     CertSourceSelfSigned,
		KeyType:    "ecdsa",
		ValidDays:  825,
		CommonName: DefaultServerName,
		DNSNames:   []string{DefaultServerName},
	}
}

// NormalizeEncryptedDNSConfig 校验与修补加密 DNS 配置。
//
// 端口越界会被改回默认值而不是留着一个必然监听失败的值：
// 与区配置不同，这里没有「用户输入被静默丢弃」的问题——
// 端口本就是短小的枚举，回落到约定端口比拒绝保存更可用。
func NormalizeEncryptedDNSConfig(cfg *EncryptedDNSConfig) {
	if cfg == nil {
		return
	}
	if !IsValidCertSource(cfg.Cert.Source) {
		cfg.Cert.Source = CertSourceSelfSigned
	}
	if cfg.Cert.KeyType != "rsa" && cfg.Cert.KeyType != "ecdsa" {
		cfg.Cert.KeyType = "ecdsa"
	}
	if cfg.Cert.ValidDays < 1 || cfg.Cert.ValidDays > 3650 {
		cfg.Cert.ValidDays = 825
	}
	cfg.Cert.CertFile = strings.TrimSpace(cfg.Cert.CertFile)
	cfg.Cert.KeyFile = strings.TrimSpace(cfg.Cert.KeyFile)
	cfg.Cert.CommonName = strings.TrimSpace(cfg.Cert.CommonName)
	cfg.Cert.DNSNames = trimNonEmpty(cfg.Cert.DNSNames)
	cfg.Cert.IPAddresses = trimNonEmpty(cfg.Cert.IPAddresses)

	cfg.ListenAddress = strings.TrimSpace(cfg.ListenAddress)
	cfg.ServerName = strings.TrimSpace(cfg.ServerName)
	if cfg.ServerName == "" {
		cfg.ServerName = DefaultServerName
	}
	// 描述文件 UUID 会原样进 XML 与载荷标识，带空白会让标识对不上；
	// 这里只规整、不重新生成——换了 UUID 设备会当成另一份描述文件
	cfg.UUID = strings.TrimSpace(cfg.UUID)

	cfg.ReverseProxy.TrustedSources = trimNonEmpty(cfg.ReverseProxy.TrustedSources)
	cfg.ReverseProxy.ClientIPHeader = strings.TrimSpace(cfg.ReverseProxy.ClientIPHeader)

	if !isValidPort(cfg.DoTPort) {
		cfg.DoTPort = DefaultDoTPort
	}
	if !isValidPort(cfg.DoHPort) {
		cfg.DoHPort = DefaultDoHPort
	}
	if !isValidPort(cfg.DoQPort) {
		cfg.DoQPort = DefaultDoQPort
	}

	// 路径必须以 / 开头：DDR 与移动端描述文件都会把它直接拼进 URL，
	// 少了斜杠会拼出一个客户端解析不了的地址
	cfg.DoHPath = strings.TrimSpace(cfg.DoHPath)
	if cfg.DoHPath == "" {
		cfg.DoHPath = DefaultDoHPath
	} else if !strings.HasPrefix(cfg.DoHPath, "/") {
		cfg.DoHPath = "/" + cfg.DoHPath
	}
}

// NormalizeCertConfig 单独归一化证书配置，供证书导入等局部操作复用
func NormalizeCertConfig(cfg *CertConfig) {
	if cfg == nil {
		return
	}
	wrapped := EncryptedDNSConfig{Cert: *cfg}
	NormalizeEncryptedDNSConfig(&wrapped)
	*cfg = wrapped.Cert
}

// IsValidCertSource 判断证书来源取值是否受支持
func IsValidCertSource(src string) bool {
	switch src {
	case CertSourceSelfSigned, CertSourceFile, CertSourcePKCS12:
		return true
	default:
		return false
	}
}

// DoHURLs 按候选主机名生成 DoH 地址列表，供界面直接展示与复制。
//
// 443 端口不写进地址：客户端配置里 https://dns.lan/dns-query 与
// https://dns.lan:443/dns-query 等价，多一个显式端口只会让用户
// 以为非用不可，也更容易在粘贴时粘错。
func DoHURLs(hosts []string, port int, path string) []string {
	if !isValidPort(port) {
		port = DefaultDoHPort
	}
	path = strings.TrimSpace(path)
	if path == "" {
		path = DefaultDoHPath
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}

	out := make([]string, 0, len(hosts))
	seen := make(map[string]bool, len(hosts))
	for _, h := range hosts {
		h = strings.TrimSpace(h)
		if h == "" || seen[h] {
			continue
		}
		seen[h] = true
		// IPv6 字面量必须加方括号，否则 https://::1/dns-query 解析不了
		authority := h
		if net.ParseIP(h) != nil && strings.Contains(h, ":") {
			authority = "[" + h + "]"
		}
		if port != DefaultDoHPort {
			authority = authority + ":" + strconv.Itoa(port)
		}
		out = append(out, "https://"+authority+path)
	}
	return out
}

// NormalizeTrustedSources 校验可信代理来源列表。
//
// 非法条目直接报错而不是跳过：可信列表的每一项都决定「谁会采信转发头」，
// 静默丢弃一个写错的 CIDR 会让用户以为某台代理已被信任，实际却是被忽略的，
// 反过来又可能因为漏配而让真实终端 IP 取不到。宁可让保存失败。
func NormalizeTrustedSources(entries []string) ([]string, error) {
	out := make([]string, 0, len(entries))
	seen := make(map[string]bool, len(entries))
	for _, raw := range entries {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		if strings.Contains(entry, "/") {
			if _, _, err := net.ParseCIDR(entry); err != nil {
				return nil, fmt.Errorf("可信来源网段 %q 无效: %w", entry, err)
			}
		} else if net.ParseIP(entry) == nil {
			return nil, fmt.Errorf("可信来源 %q 不是合法的 IP 或 CIDR", entry)
		}
		if seen[entry] {
			continue
		}
		seen[entry] = true
		out = append(out, entry)
	}
	return out, nil
}

// IsUnrestrictedTrust 判断某条目是否等于「信任所有人」。
//
// 前缀长度为 0 的 CIDR（0.0.0.0/0 与 ::/0）意味着任何直连对端都被信任，
// 于是调用方可以随意伪造 X-Forwarded-For 来伪装成白名单成员、
// 并让按 IP 计数的限速各自为政。这不是普通配置项，界面必须二次确认。
func IsUnrestrictedTrust(entry string) bool {
	entry = strings.TrimSpace(entry)
	if !strings.Contains(entry, "/") {
		return false
	}
	_, ipNet, err := net.ParseCIDR(entry)
	if err != nil {
		return false
	}
	ones, _ := ipNet.Mask.Size()
	return ones == 0
}

// HasUnrestrictedTrust 报告列表中是否存在全放行条目
func HasUnrestrictedTrust(entries []string) bool {
	for _, e := range entries {
		if IsUnrestrictedTrust(e) {
			return true
		}
	}
	return false
}

// CertInfo 服务端证书的只读摘要，供界面展示。
//
// 有意不含私钥与完整证书体：界面需要的是「这证书是谁、几时过期、
// 覆盖了哪些名字」，回传 DER 只会让一个只读接口变成密钥材料的搬运通道。
type CertInfo struct {
	// Source 当前证书来源
	Source string `json:"source"`
	// Subject 证书主体
	Subject string `json:"subject"`
	// Issuer 签发者
	Issuer string `json:"issuer"`
	// SerialNumber 序列号（大写十六进制）
	SerialNumber string `json:"serialNumber"`
	// NotBefore / NotAfter 有效期边界
	NotBefore string `json:"notBefore"`
	NotAfter  string `json:"notAfter"`
	// DNSNames / IPAddresses 证书覆盖的 SAN
	DNSNames    []string `json:"dnsNames"`
	IPAddresses []string `json:"ipAddresses"`
	// DaysRemaining 距过期的天数，已过期为负
	DaysRemaining int `json:"daysRemaining"`
	// Fingerprint SHA-256 指纹（冒号分隔大写十六进制），供客户端核对
	Fingerprint string `json:"fingerprint"`
	// ChainLength 证书链长度（自签为 1）
	ChainLength int `json:"chainLength"`
	// Loaded 证书是否已成功载入
	Loaded bool `json:"loaded"`
	// Error 加载失败原因；Loaded 为 false 时给出
	Error string `json:"error,omitempty"`
	// SelfSigned 是否为自签证书
	SelfSigned bool `json:"selfSigned"`
}

// isSelfSigned 判断证书是否自签。
//
// 比较的是原始签发者字节而不是解析后的对象：解析后的对象会做规范化，
// 两个本不相同的名字可能因此被判定为相等，凭空得出「自签」的结论。
func isSelfSigned(cert *x509.Certificate) bool {
	if cert == nil {
		return false
	}
	return string(cert.RawIssuer) == string(cert.RawSubject)
}

// trimNonEmpty 去掉每项两端空白并丢弃空项
func trimNonEmpty(in []string) []string {
	out := make([]string, 0, len(in))
	for _, s := range in {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// isValidPort 判断端口号是否在可用范围内。
//
// 0 视为非法：绑定 0 会让内核随机分配端口，而加密 DNS 的端口是要
// 告诉客户端的，随机端口等于没配。
func isValidPort(port int) bool {
	return port > 0 && port <= 65535
}
