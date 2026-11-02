package core

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"sort"
	"strings"
	"time"
)

// SelfSignedCert 一张自签证书及其私钥的 PEM 编码
type SelfSignedCert struct {
	CertPEM []byte
	KeyPEM  []byte
}

// GenerateSelfSignedCert 按配置生成一张自签证书。
//
// 有效期向后推一天起算：宿主机与客户端时钟常有几秒到几分钟的偏差，
// 以「此刻」为 NotBefore 会让证书在刚生成的一小段时间里被判为尚未生效，
// 客户端报出的却是笼统的证书校验失败。
func GenerateSelfSignedCert(cfg CertConfig) (*SelfSignedCert, error) {
	NormalizeCertConfig(&cfg)

	key, err := generateCertKey(cfg.KeyType)
	if err != nil {
		return nil, err
	}

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("生成证书序列号失败: %w", err)
	}

	validDays := cfg.ValidDays
	if validDays <= 0 {
		validDays = 825
	}
	now := time.Now()

	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   certCommonName(cfg),
			Organization: []string{"DITING"},
		},
		NotBefore:             now.Add(-24 * time.Hour),
		NotAfter:              now.Add(time.Duration(validDays) * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  true,
		DNSNames:              cfg.DNSNames,
	}

	for _, raw := range cfg.IPAddresses {
		ip := net.ParseIP(raw)
		if ip == nil {
			return nil, fmt.Errorf("证书 SAN 中的 IP 地址无效: %q", raw)
		}
		tmpl.IPAddresses = append(tmpl.IPAddresses, ip)
	}
	// 缺省补上回环：客户端多半就在本机，而一个不含 127.0.0.1 的证书
	// 会让本机自测（kdig +tls @127.0.0.1）在证书校验这一步就失败
	if len(tmpl.DNSNames) == 0 && len(tmpl.IPAddresses) == 0 {
		tmpl.IPAddresses = []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")}
	}

	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, key.Public(), key)
	if err != nil {
		return nil, fmt.Errorf("生成自签证书失败: %w", err)
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM, err := encodePrivateKey(key)
	if err != nil {
		return nil, err
	}
	return &SelfSignedCert{CertPEM: certPEM, KeyPEM: keyPEM}, nil
}

// generateCertKey 按类型生成私钥，返回私钥与其签名接口
func generateCertKey(keyType string) (crypto.Signer, error) {
	if keyType == "rsa" {
		key, err := rsa.GenerateKey(rand.Reader, 3072)
		if err != nil {
			return nil, fmt.Errorf("生成 RSA 私钥失败: %w", err)
		}
		return key, nil
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("生成 ECDSA 私钥失败: %w", err)
	}
	return key, nil
}

// encodePrivateKey 把私钥编码成 PKCS#8 PEM。
//
// 统一用 PKCS#8 而不是各类型自有的 EC/RSA 格式：一个 decoder 处理所有
// 密钥类型，读取路径不必按类型分派。
func encodePrivateKey(key any) ([]byte, error) {
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("编码私钥失败: %w", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), nil
}

// certCommonName 决定自签证书的 CN，未配置时取覆盖的第一个名字
func certCommonName(cfg CertConfig) string {
	if cfg.CommonName != "" {
		return cfg.CommonName
	}
	if len(cfg.DNSNames) > 0 {
		return cfg.DNSNames[0]
	}
	if len(cfg.IPAddresses) > 0 {
		return cfg.IPAddresses[0]
	}
	return DefaultServerName
}

// DeriveCertNames 由监听地址与服务器名推导出证书应有的 SAN。
//
// 用户往往只填了「监听 0.0.0.0:853」和「服务器名叫 dns.lan」，不会主动
// 想到证书里也得有这两个名字。少了它们，客户端拿到的是一张「域名对不上」
// 的证书，而错误信息多半只提证书无效。界面在生成自签证书前调用本函数，
// 把用户填过的信息补成 SAN 供其确认。
func DeriveCertNames(serverName, listenAddress string, extra []string) (dnsNames, ipAddrs []string) {
	seen := map[string]bool{}
	addDNS := func(name string) {
		name = normalizeCertName(name)
		if name == "" || seen["d:"+name] {
			return
		}
		seen["d:"+name] = true
		dnsNames = append(dnsNames, name)
	}
	addIP := func(raw string) {
		ip := net.ParseIP(raw)
		if ip == nil || seen["i:"+ip.String()] {
			return
		}
		seen["i:"+ip.String()] = true
		ipAddrs = append(ipAddrs, ip.String())
	}

	addDNS(serverName)
	if host, _, err := net.SplitHostPort(listenAddress); err == nil {
		addHost(host, addDNS, addIP)
	} else if listenAddress != "" {
		addHost(listenAddress, addDNS, addIP)
	}
	for _, name := range extra {
		addHost(name, addDNS, addIP)
	}

	sort.Strings(dnsNames)
	return dnsNames, ipAddrs
}

// addHost 按「IP 还是域名」把单个主机串分派到对应列表
//
// 未指定地址（0.0.0.0 / ::）一律跳过：那是「监听全部网卡」的写法，
// 不是任何一台主机的名字，把它写进证书只会多出一个毫无意义的 SAN。
func addHost(host string, addDNS, addIP func(string)) {
	host = normalizeCertName(host)
	if host == "" {
		return
	}
	ip := net.ParseIP(host)
	if ip == nil {
		addDNS(host)
		return
	}
	if ip.IsUnspecified() {
		return
	}
	addIP(host)
}

// normalizeCertName 去掉两端的空白，空名字返回空串
func normalizeCertName(name string) string {
	return strings.TrimSpace(name)
}
