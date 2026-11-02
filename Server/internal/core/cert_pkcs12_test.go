package core

import (
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
)

// 素材刻意用 OpenSSL 3.x 的默认参数导出（PBES2 + AES-256-CBC +
// PBKDF2-SHA256），也就是真实世界里的 .p12 长什么样。若改用 -legacy
// 导出的 3DES/SHA-1 容器，这个用例就再也测不到 gx/crypto 那个坑了。
const pkcs12Fixture = "testdata/dns-lan.p12"
const pkcs12FixturePassword = "s3cret"

func readFixture(t *testing.T) []byte {
	t.Helper()
	b, err := os.ReadFile(pkcs12Fixture)
	if err != nil {
		t.Fatalf("读取 PKCS#12 测试素材失败: %v", err)
	}
	return b
}

// PKCS#12 是 Windows 上证书管理的通行格式，导入路径必须端到端可用。
// 素材由 openssl 生成的固定文件，覆盖「解析 → 私钥重编码 → 落盘 →
// 重载」这条完整链路。
func TestCert_ImportPKCS12RoundTrip(t *testing.T) {
	m, dir := newTestCertManager(t)
	if err := m.ImportPKCS12(readFixture(t), pkcs12FixturePassword); err != nil {
		t.Fatalf("导入 PKCS#12 失败: %v", err)
	}

	info := m.Info()
	if !info.Loaded {
		t.Fatalf("导入后应载入成功: %+v", info)
	}
	if len(info.DNSNames) != 1 || info.DNSNames[0] != "dns.lan" {
		t.Fatalf("导入后 SAN 不符: %v", info.DNSNames)
	}
	if !info.SelfSigned {
		t.Fatal("素材自签，应被识别为自签证书")
	}

	// PKCS#12 把私钥包在容器里，落盘前必须解出来重新编码成 PEM，
	// 否则下一次重载按 PEM 去读会拿到一段二进制
	keyPEM, err := os.ReadFile(filepath.Join(dir, ImportedKeyFileName))
	if err != nil {
		t.Fatalf("私钥未落盘: %v", err)
	}
	block, _ := pem.Decode(keyPEM)
	if block == nil || block.Type != "PRIVATE KEY" {
		t.Fatalf("落盘私钥应为 PKCS#8 PEM，实得 %v", block)
	}

	// 重载走的是文件路径，与导入时的 PKCS#12 路径完全不同，这里确认它也能通过
	m.Reload()
	if !m.Info().Loaded {
		t.Fatal("重载后证书仍应可用")
	}
}

func TestCert_ImportPKCS12WrongPassword(t *testing.T) {
	m, _ := newTestCertManager(t)
	if err := m.ImportPKCS12(readFixture(t), "wrong"); err == nil {
		t.Fatal("口令错误时应拒绝导入")
	}
	if m.Info().Loaded {
		t.Fatal("失败后不应载入任何证书")
	}
}

func TestCert_ImportPKCS12Garbage(t *testing.T) {
	m, _ := newTestCertManager(t)
	if err := m.ImportPKCS12([]byte("not a p12"), "x"); err == nil {
		t.Fatal("非 PKCS#12 输入应被拒绝")
	}
}
