package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCert_ImportPEM(t *testing.T) {
	m, _ := newTestCertManager(t)
	gen, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatal(err)
	}

	if err := m.ImportPEM(gen.CertPEM, gen.KeyPEM); err != nil {
		t.Fatalf("导入 PEM 失败: %v", err)
	}
	info := m.Info()
	if !info.Loaded {
		t.Fatalf("导入后应载入成功: %+v", info)
	}
	if m.GetConfig().Source != CertSourceFile {
		t.Fatalf("导入后来源应切为文件，实得 %q", m.GetConfig().Source)
	}
}

// 不匹配的一对必须在导入时就拒绝，而不是留到下次启动时以握手失败呈现
func TestCert_ImportPEMMismatchedRejected(t *testing.T) {
	m, _ := newTestCertManager(t)
	a, _ := GenerateSelfSignedCert(selfSignedCfg())
	bCfg := selfSignedCfg()
	bCfg.CommonName = "other.lan"
	bCfg.DNSNames = []string{"other.lan"}
	b, _ := GenerateSelfSignedCert(bCfg)

	if err := m.ImportPEM(a.CertPEM, b.KeyPEM); err == nil {
		t.Fatal("证书与私钥不匹配时应拒绝导入")
	}
	if m.Info().Loaded {
		t.Fatal("拒绝后不应载入任何证书")
	}
}

func TestCert_ImportPEMGarbageRejected(t *testing.T) {
	m, _ := newTestCertManager(t)
	if err := m.ImportPEM([]byte("not pem"), []byte("also not pem")); err == nil {
		t.Fatal("非 PEM 输入应被拒绝")
	}
}

func TestCert_LoadFromFiles(t *testing.T) {
	dir := t.TempDir()
	gen, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatal(err)
	}
	certPath := filepath.Join(dir, "c.pem")
	keyPath := filepath.Join(dir, "k.pem")
	if err := os.WriteFile(certPath, gen.CertPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, gen.KeyPEM, 0o600); err != nil {
		t.Fatal(err)
	}

	m := NewCertManager(dir, CertConfig{
		Source:   CertSourceFile,
		CertFile: certPath,
		KeyFile:  keyPath,
	})
	info := m.Info()
	if !info.Loaded {
		t.Fatalf("应从 PEM 文件载入: %+v", info)
	}
	if info.ChainLength != 1 {
		t.Fatalf("链长应为 1，实得 %d", info.ChainLength)
	}
}

func TestCert_ResolvePathsRejectsIncompleteConfig(t *testing.T) {
	dir := t.TempDir()

	if _, _, _, err := resolveCertPaths(dir, CertConfig{Source: CertSourceFile}); err == nil {
		t.Fatal("缺少证书路径应报错")
	}
	if _, _, _, err := resolveCertPaths(dir, CertConfig{
		Source: CertSourceFile, CertFile: "c.pem",
	}); err == nil {
		t.Fatal("缺少私钥路径应报错")
	}
	if _, _, _, err := resolveCertPaths("", CertConfig{Source: CertSourceSelfSigned}); err == nil {
		t.Fatal("缺少证书目录应报错")
	}

	// PKCS#12 的证书与私钥同在一个文件
	c, k, pw, err := resolveCertPaths(dir, CertConfig{
		Source: CertSourcePKCS12, CertFile: "bundle.p12", PKCS12Password: "s3cret",
	})
	if err != nil {
		t.Fatalf("PKCS#12 路径解析失败: %v", err)
	}
	if c != k || pw != "s3cret" {
		t.Fatalf("PKCS#12 路径解析不符: %q %q %q", c, k, pw)
	}
}

func TestCert_InfoFingerprintFormat(t *testing.T) {
	m, _ := newTestCertManager(t)
	if _, err := m.EnsureSelfSigned(selfSignedCfg()); err != nil {
		t.Fatal(err)
	}
	info := m.Info()
	parts := strings.Split(info.Fingerprint, ":")
	if len(parts) != 32 {
		t.Fatalf("SHA-256 指纹应有 32 段，实得 %d", len(parts))
	}
	for _, p := range parts {
		if len(p) != 2 || strings.ToUpper(p) != p {
			t.Fatalf("指纹段应为两位大写十六进制，实得 %q", p)
		}
	}
	if info.DaysRemaining <= 0 {
		t.Fatalf("有效期剩余天数应为正，实得 %d", info.DaysRemaining)
	}
}

func TestCert_ReloadAfterFileChange(t *testing.T) {
	dir := t.TempDir()
	first := selfSignedCfg()
	first.DNSNames = []string{"first.lan"}
	first.CommonName = "first.lan"
	gen1, _ := GenerateSelfSignedCert(first)
	certPath := filepath.Join(dir, "c.pem")
	keyPath := filepath.Join(dir, "k.pem")
	os.WriteFile(certPath, gen1.CertPEM, 0o600)
	os.WriteFile(keyPath, gen1.KeyPEM, 0o600)

	m := NewCertManager(dir, CertConfig{Source: CertSourceFile, CertFile: certPath, KeyFile: keyPath})
	if got := m.Info().DNSNames; len(got) != 1 || got[0] != "first.lan" {
		t.Fatalf("初次载入不符: %v", got)
	}

	second := selfSignedCfg()
	second.DNSNames = []string{"second.lan"}
	second.CommonName = "second.lan"
	gen2, _ := GenerateSelfSignedCert(second)
	os.WriteFile(certPath, gen2.CertPEM, 0o600)
	os.WriteFile(keyPath, gen2.KeyPEM, 0o600)

	m.Reload()
	if got := m.Info().DNSNames; len(got) != 1 || got[0] != "second.lan" {
		t.Fatalf("重载后应换上新的 SAN，实得 %v", got)
	}
}

// 证书链必须按顺序解析，且跳过非证书块
func TestCert_ParseChainSkipsNonCertBlocks(t *testing.T) {
	gen, _ := GenerateSelfSignedCert(selfSignedCfg())
	mixed := append([]byte("-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----\n"), gen.CertPEM...)

	chain, err := parseChain(mixed)
	if err != nil {
		t.Fatalf("解析失败: %v", err)
	}
	if len(chain) != 1 {
		t.Fatalf("应只解析出 1 张证书，实得 %d", len(chain))
	}
}

func TestCert_ParseChainEmpty(t *testing.T) {
	if _, err := parseChain([]byte("nothing here")); err == nil {
		t.Fatal("无证书块时应报错")
	}
}

// 导入件必须与自签固定名隔离：共用一对文件名时，改回 self_signed 会复用
// 导入证书（永不生成自签），点「重新签发」又会把导入件覆盖掉。
func TestCert_ImportDoesNotCollideWithSelfSigned(t *testing.T) {
	m, dir := newTestCertManager(t)

	imported, err := GenerateSelfSignedCert(selfSignedCfg())
	if err != nil {
		t.Fatal(err)
	}
	if err := m.ImportPEM(imported.CertPEM, imported.KeyPEM); err != nil {
		t.Fatalf("导入 PEM 失败: %v", err)
	}
	importedOnDisk, err := os.ReadFile(filepath.Join(dir, ImportedCertFileName))
	if err != nil {
		t.Fatalf("导入件未落盘: %v", err)
	}

	// 切回自签来源后必须真正生成一张自签证书，而不是复用导入件
	cfg := selfSignedCfg()
	created, err := m.EnsureSelfSigned(cfg)
	if err != nil {
		t.Fatalf("生成自签证书失败: %v", err)
	}
	if !created {
		t.Fatal("来源切回 self_signed 后应重新生成，而不是复用导入件")
	}
	if m.GetConfig().Source != CertSourceSelfSigned {
		t.Fatalf("来源应切回自签，实得 %q", m.GetConfig().Source)
	}

	// 重签只动自签件，导入件必须原样保留
	if err := m.RegenerateSelfSigned(cfg); err != nil {
		t.Fatalf("重签失败: %v", err)
	}
	after, err := os.ReadFile(filepath.Join(dir, ImportedCertFileName))
	if err != nil {
		t.Fatalf("导入件丢失: %v", err)
	}
	if string(after) != string(importedOnDisk) {
		t.Fatal("重签覆写了导入证书")
	}
}

// 临近到期的自签证书必须被主动换掉：客户端握手会直接拒绝过期证书，
// 而本端监听器不会报错，只靠「文件存在」永远发现不了。
func TestCert_RenewSelfSignedWhenExpiringSoon(t *testing.T) {
	m, dir := newTestCertManager(t)
	cfg := selfSignedCfg()
	cfg.ValidDays = 1
	if _, err := m.EnsureSelfSigned(cfg); err != nil {
		t.Fatal(err)
	}

	// 重写一对 1 天有效期的证书，模拟 825 天自签已进入尾期
	shortCfg := selfSignedCfg()
	shortCfg.ValidDays = 1
	gen, err := GenerateSelfSignedCert(shortCfg)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, SelfSignedCertFileName), gen.CertPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, SelfSignedKeyFileName), gen.KeyPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	m.Reload()
	if h := m.Health(); h.Expired || !h.Loaded {
		t.Fatalf("刚生成的证书不应过期: %+v", h)
	}
	if h := m.Health(); h.DaysRemaining > int(CertRenewBefore.Hours()/24) {
		t.Fatalf("有效期 1 天的证书应落入续签窗口: %+v", h)
	}
	renewed, err := m.RenewSelfSignedIfNeeded(selfSignedCfg())
	if err != nil {
		t.Fatalf("续签失败: %v", err)
	}
	if !renewed {
		t.Fatal("即将到期的自签证书应被续签")
	}
}
