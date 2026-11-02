package core

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func selfSignedCfg() CertConfig {
	cfg := DefaultCertConfig()
	cfg.CommonName = "dns.lan"
	cfg.DNSNames = []string{"dns.lan"}
	cfg.ValidDays = 30
	return cfg
}

func newTestCertManager(t *testing.T) (*CertManager, string) {
	t.Helper()
	dir := t.TempDir()
	return NewCertManager(dir, selfSignedCfg()), dir
}

func TestCert_EnsureSelfSignedCreates(t *testing.T) {
	m, dir := newTestCertManager(t)

	created, err := m.EnsureSelfSigned(selfSignedCfg())
	if err != nil {
		t.Fatalf("生成自签证书失败: %v", err)
	}
	if !created {
		t.Fatal("首次调用应生成证书")
	}

	if _, err := os.Stat(filepath.Join(dir, SelfSignedCertFileName)); err != nil {
		t.Fatalf("证书文件未落盘: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, SelfSignedKeyFileName)); err != nil {
		t.Fatalf("私钥文件未落盘: %v", err)
	}

	info := m.Info()
	if !info.Loaded || info.Error != "" {
		t.Fatalf("证书应载入成功: %+v", info)
	}
	if !info.SelfSigned {
		t.Fatal("应识别为自签证书")
	}
	if len(info.DNSNames) != 1 || info.DNSNames[0] != "dns.lan" {
		t.Fatalf("SAN 不符: %v", info.DNSNames)
	}
}

// 私钥必须只有属主可读：同机其他用户能读到，就等于谁都能冒充这台服务器
//
// Windows 上 os.Stat 回报的一律是 0666，位权限模型在那里不被遵循，
// 断言只对类 Unix 有意义。
func TestCert_SelfSignedKeyIsPrivate(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows 不遵循 POSIX 权限位")
	}
	m, dir := newTestCertManager(t)
	if _, err := m.EnsureSelfSigned(selfSignedCfg()); err != nil {
		t.Fatalf("生成失败: %v", err)
	}

	for _, name := range []string{SelfSignedCertFileName, SelfSignedKeyFileName} {
		info, err := os.Stat(filepath.Join(dir, name))
		if err != nil {
			t.Fatalf("stat %s: %v", name, err)
		}
		if perm := info.Mode().Perm(); perm&0o077 != 0 {
			t.Fatalf("%s 权限 %o 允许属主之外的访问", name, perm)
		}
	}
}

// 复用而非重签：客户端（尤其 iOS 描述文件）会记住已信任的证书
func TestCert_EnsureSelfSignedReusesExisting(t *testing.T) {
	m, dir := newTestCertManager(t)
	if _, err := m.EnsureSelfSigned(selfSignedCfg()); err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	before, err := os.ReadFile(filepath.Join(dir, SelfSignedCertFileName))
	if err != nil {
		t.Fatal(err)
	}

	created, err := m.EnsureSelfSigned(selfSignedCfg())
	if err != nil {
		t.Fatalf("二次调用失败: %v", err)
	}
	if created {
		t.Fatal("已存在证书时不应重新生成")
	}
	after, _ := os.ReadFile(filepath.Join(dir, SelfSignedCertFileName))
	if string(before) != string(after) {
		t.Fatal("二次调用改写了证书文件")
	}
}

func TestCert_GenerateRSA(t *testing.T) {
	cfg := selfSignedCfg()
	cfg.KeyType = "rsa"
	gen, err := GenerateSelfSignedCert(cfg)
	if err != nil {
		t.Fatalf("生成 RSA 自签证书失败: %v", err)
	}

	block, _ := pem.Decode(gen.KeyPEM)
	if block == nil {
		t.Fatal("私钥 PEM 解码失败")
	}
	// 统一 PKCS#8，读取路径不必按密钥类型分派
	if block.Type != "PRIVATE KEY" {
		t.Fatalf("私钥应以 PKCS#8 编码，实得 %q", block.Type)
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		t.Fatalf("解析 PKCS#8 私钥失败: %v", err)
	}
	if _, ok := key.(*rsa.PrivateKey); !ok {
		t.Fatalf("应为 RSA 私钥，实得 %T", key)
	}
}

func TestCert_GenerateECDSA(t *testing.T) {
	gen, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	block, _ := pem.Decode(gen.KeyPEM)
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		t.Fatalf("解析私钥失败: %v", err)
	}
	ec, ok := key.(*ecdsa.PrivateKey)
	if !ok {
		t.Fatalf("默认应为 ECDSA 私钥，实得 %T", key)
	}
	if ec.Curve != elliptic.P256() {
		t.Fatalf("默认曲线应为 P-256，实得 %v", ec.Curve.Params().Name)
	}
}

// NotBefore 必须早于当前时刻：宿主机与客户端时钟有偏差时，
// 以「此刻」起算会让刚生成的证书被判为尚未生效
func TestCert_NotBeforeBackdated(t *testing.T) {
	gen, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	block, _ := pem.Decode(gen.CertPEM)
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("解析证书失败: %v", err)
	}
	if !cert.NotBefore.Before(time.Now()) {
		t.Fatalf("NotBefore 应早于当前时刻，实得 %v", cert.NotBefore)
	}
}

// 未给任何名字时补回环地址，否则本机自测会在证书校验这一步失败
func TestCert_DefaultSANIsLoopback(t *testing.T) {
	cfg := CertConfig{Source: CertSourceSelfSigned}
	gen, err := GenerateSelfSignedCert(cfg)
	if err != nil {
		t.Fatalf("生成失败: %v", err)
	}
	block, _ := pem.Decode(gen.CertPEM)
	cert, _ := x509.ParseCertificate(block.Bytes)
	if len(cert.IPAddresses) != 2 {
		t.Fatalf("应补上两个回环地址，实得 %v", cert.IPAddresses)
	}
}

func TestCert_GenerateRejectsBadIP(t *testing.T) {
	cfg := selfSignedCfg()
	cfg.IPAddresses = []string{"not-an-ip"}
	if _, err := GenerateSelfSignedCert(cfg); err == nil {
		t.Fatal("非法 IP 应被拒绝")
	}
}

func TestCert_TLSConfigUsable(t *testing.T) {
	m, _ := newTestCertManager(t)
	if _, err := m.EnsureSelfSigned(selfSignedCfg()); err != nil {
		t.Fatalf("生成失败: %v", err)
	}

	cfg, err := m.TLSConfig("dot")
	if err != nil {
		t.Fatalf("取 TLS 配置失败: %v", err)
	}
	if cfg.MinVersion < tls.VersionTLS12 {
		t.Fatalf("最低 TLS 版本过低: %x", cfg.MinVersion)
	}
	if len(cfg.NextProtos) != 1 || cfg.NextProtos[0] != "dot" {
		t.Fatalf("ALPN 未透传: %v", cfg.NextProtos)
	}
	if len(cfg.Certificates) != 1 {
		t.Fatal("应提供一张证书")
	}
}

// 证书不可用时必须报错，而不是取一张空证书顶上去
func TestCert_TLSConfigErrorsWhenUnusable(t *testing.T) {
	dir := t.TempDir()
	cfg := selfSignedCfg()
	cfg.Source = CertSourceFile
	cfg.CertFile = filepath.Join(dir, "missing.crt")
	cfg.KeyFile = filepath.Join(dir, "missing.key")
	m := NewCertManager(dir, cfg)

	if _, err := m.TLSConfig(); err == nil {
		t.Fatal("证书缺失时应返回错误")
	}
	info := m.Info()
	if info.Loaded || info.Error == "" {
		t.Fatalf("应如实记录失败原因: %+v", info)
	}
}

// NextProtos 是调用方的切片，不能被内部改动污染
func TestCert_TLSConfigCopiesNextProtos(t *testing.T) {
	m, _ := newTestCertManager(t)
	if _, err := m.EnsureSelfSigned(selfSignedCfg()); err != nil {
		t.Fatal(err)
	}
	protos := []string{"h2", "http/1.1"}
	cfg, err := m.TLSConfig(protos...)
	if err != nil {
		t.Fatal(err)
	}
	protos[0] = "mutated"
	if cfg.NextProtos[0] != "h2" {
		t.Fatal("内部切片不应与调用方共享底层数组")
	}
}
