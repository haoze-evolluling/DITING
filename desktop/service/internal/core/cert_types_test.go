package core

import (
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"testing"
)

func TestCert_NormalizeEncryptedConfig(t *testing.T) {
	cfg := EncryptedDNSConfig{
		Cert:    CertConfig{Source: "bogus", KeyType: "dsa", ValidDays: 0},
		DoTPort: 70000,
		DoHPort: -1,
		DoQPort: 0,
		DoHPath: "dns-query",
	}
	NormalizeEncryptedDNSConfig(&cfg)

	if cfg.Cert.Source != CertSourceSelfSigned {
		t.Fatalf("非法来源应回落自签，实得 %q", cfg.Cert.Source)
	}
	if cfg.Cert.KeyType != "ecdsa" {
		t.Fatalf("非法密钥类型应回落 ecdsa，实得 %q", cfg.Cert.KeyType)
	}
	if cfg.Cert.ValidDays != 825 {
		t.Fatalf("非法有效期应回落 825，实得 %d", cfg.Cert.ValidDays)
	}
	if cfg.DoTPort != DefaultDoTPort || cfg.DoHPort != DefaultDoHPort || cfg.DoQPort != DefaultDoQPort {
		t.Fatalf("越界端口应回落默认值: %d %d %d", cfg.DoTPort, cfg.DoHPort, cfg.DoQPort)
	}
	// 缺少前导斜杠会拼出客户端解析不了的 URL
	if cfg.DoHPath != "/dns-query" {
		t.Fatalf("路径应补上前导斜杠，实得 %q", cfg.DoHPath)
	}
}

func TestCert_NormalizeNilSafe(t *testing.T) {
	NormalizeEncryptedDNSConfig(nil)
	NormalizeCertConfig(nil)
}

func TestCert_DefaultDisabled(t *testing.T) {
	cfg := DefaultEncryptedDNSConfig()
	if cfg.Enabled || cfg.DoTEnabled || cfg.DoHEnabled || cfg.DoQEnabled {
		t.Fatal("加密 DNS 服务默认必须全部关闭")
	}
	if cfg.DoHPath != DefaultDoHPath {
		t.Fatalf("默认路径不符: %q", cfg.DoHPath)
	}
}

func TestCert_DeriveCertNames(t *testing.T) {
	dnsNames, ipAddrs := DeriveCertNames("dns.lan", "0.0.0.0:853", []string{"192.168.1.10", "extra.lan"})

	if len(dnsNames) != 2 {
		t.Fatalf("应得到两个域名，实得 %v", dnsNames)
	}
	if dnsNames[0] != "dns.lan" || dnsNames[1] != "extra.lan" {
		t.Fatalf("域名应排序，实得 %v", dnsNames)
	}
	if len(ipAddrs) != 1 || ipAddrs[0] != "192.168.1.10" {
		t.Fatalf("IP 列表不符: %v", ipAddrs)
	}
}

// 监听地址是裸 IP 时也要进 SAN，否则按 IP 连接会域名不匹配
func TestCert_DeriveCertNamesFromBareIP(t *testing.T) {
	_, ipAddrs := DeriveCertNames("", "10.0.0.5", nil)
	if len(ipAddrs) != 1 || ipAddrs[0] != "10.0.0.5" {
		t.Fatalf("裸 IP 监听地址应进 SAN: %v", ipAddrs)
	}
}

func TestCert_DeriveCertNamesDedupes(t *testing.T) {
	dnsNames, ipAddrs := DeriveCertNames("dns.lan", "dns.lan:853", []string{"dns.lan", "1.1.1.1", "1.1.1.1"})
	if len(dnsNames) != 1 {
		t.Fatalf("重复域名应去重，实得 %v", dnsNames)
	}
	if len(ipAddrs) != 1 {
		t.Fatalf("重复 IP 应去重，实得 %v", ipAddrs)
	}
}

func TestCert_DeriveCertNamesEmpty(t *testing.T) {
	dnsNames, ipAddrs := DeriveCertNames("", "", nil)
	if len(dnsNames) != 0 || len(ipAddrs) != 0 {
		t.Fatalf("空输入不应产生名字: %v %v", dnsNames, ipAddrs)
	}
}

// 交叉验证：用 CertManager 产出的证书去校验它自己签出的叶子
func TestCert_GeneratedCertVerifiesAgainstItself(t *testing.T) {
	gen, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(gen.CertPEM) {
		t.Fatal("证书无法加入信任池")
	}
	block, _ := pem.Decode(gen.CertPEM)
	leaf, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		DNSName: "dns.lan",
		Roots:   pool,
		KeyUsages: []x509.ExtKeyUsage{
			x509.ExtKeyUsageServerAuth,
		},
	}); err != nil {
		t.Fatalf("按自身 CA 校验失败: %v", err)
	}
}

// 生成的私钥必须与证书公钥配对
func TestCert_GeneratedPairMatches(t *testing.T) {
	gen, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tls.X509KeyPair(gen.CertPEM, gen.KeyPEM); err != nil {
		t.Fatalf("证书与私钥不配对: %v", err)
	}
}

// 自签判定必须比较原始字节，不能依赖解析后的规范化结果
func TestCert_IsSelfSignedUsesRawBytes(t *testing.T) {
	if isSelfSigned(nil) {
		t.Fatal("nil 证书不应判为自签")
	}

	other := &x509.Certificate{
		RawSubject:   []byte("subject-a"),
		RawIssuer:    []byte("issuer-b"),
		Subject:      pkix.Name{CommonName: "same"},
		Issuer:       pkix.Name{CommonName: "same"},
		SerialNumber: big.NewInt(1),
	}
	if isSelfSigned(other) {
		t.Fatal("原始字节不同时不应判为自签")
	}
}
