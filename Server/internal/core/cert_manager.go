package core

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/platform/protect"

	// 选 sslmate 的实现而不用 golang.org/x/crypto/pkcs12：后者只认
	// 2000 年代的 3DES/SHA-1 容器，而 OpenSSL 3.x、Windows certutil
	// 与主流 CA 导出的都是 PBES2 + AES-256-CBC + PBKDF2-SHA256，
	// 用它读真实世界的 .p12 会直接报 unknown digest algorithm。
	"software.sslmate.com/src/go-pkcs12"
)

// 自签证书在证书目录中的固定文件名。
//
// 固定而非按 CN 命名：改了 CommonName 还不该让旧文件变成孤儿，
// 而证书目录里同时躺着几张同名不同期的文件正是「到底在用哪张」
// 这类问题的温床。
const (
	SelfSignedCertFileName = "server.crt"
	SelfSignedKeyFileName  = "server.key"
	// 导入的证书单独命名，避免与自签固定名互相覆盖
	ImportedCertFileName = "imported.crt"
	ImportedKeyFileName  = "imported.key"
)

// CertManager 管理加密 DNS 服务端证书。
//
// 证书只在磁盘上，内存里只保留解析后的 x509 与 tls.Certificate：
// 配置对象（会经 IPC 扩散到控制台）里永远不含私钥材料。
type CertManager struct {
	mu      sync.RWMutex
	dir     string
	cfg     CertConfig
	cert    *tls.Certificate
	leaf    *x509.Certificate
	chain   []*x509.Certificate
	loadErr error
	loaded  bool
}

// NewCertManager 创建证书管理器；dir 为自签证书的落盘目录
func NewCertManager(dir string, cfg CertConfig) *CertManager {
	NormalizeCertConfig(&cfg)
	m := &CertManager{dir: dir, cfg: cfg}
	m.Reload()
	return m
}

// Configure 更新配置并重新载入证书
func (m *CertManager) Configure(cfg CertConfig) {
	NormalizeCertConfig(&cfg)
	m.mu.Lock()
	m.cfg = cfg
	m.mu.Unlock()
	m.Reload()
}

// SetDir 更新证书目录（自签用）
func (m *CertManager) SetDir(dir string) {
	m.mu.Lock()
	m.dir = dir
	m.mu.Unlock()
}

// GetConfig 返回当前证书配置副本
func (m *CertManager) GetConfig() CertConfig {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.cfg
}

// Dir 返回自签证书目录
func (m *CertManager) Dir() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.dir
}

// Reload 按当前配置重新载入证书
func (m *CertManager) Reload() {
	cfg, dir := m.snapshot()

	cert, chain, err := loadCertMaterial(dir, cfg)

	m.mu.Lock()
	defer m.mu.Unlock()
	if err != nil {
		m.cert, m.leaf, m.chain = nil, nil, nil
		m.loadErr = err
		m.loaded = false
		return
	}
	m.cert, m.chain = cert, chain
	if len(chain) > 0 {
		m.leaf = chain[0]
	} else {
		m.leaf = nil
	}
	m.loadErr = nil
	m.loaded = true
}

// snapshot 取配置与目录副本，避免在载入期间持锁
func (m *CertManager) snapshot() (CertConfig, string) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.cfg, m.dir
}

// TLSConfig 返回供监听器使用的 TLS 配置；证书不可用时返回错误。
//
// 客户端用 SNI 指明要访问哪个名字，证书里没有那个名字就会校验失败。
// 这里不做「取第一张证书顶上去」的兜底：那只会把配置错误推迟到
// 客户端，且以一条与真实原因无关的报错呈现。
func (m *CertManager) TLSConfig(nextProtos ...string) (*tls.Config, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if !m.loaded || m.cert == nil {
		if m.loadErr != nil {
			return nil, fmt.Errorf("服务端证书不可用: %w", m.loadErr)
		}
		return nil, fmt.Errorf("服务端证书尚未载入")
	}
	leaf := m.leaf
	cert := m.cert

	cfg := &tls.Config{
		MinVersion:   tls.VersionTLS12,
		Certificates: []tls.Certificate{*cert},
	}
	if len(nextProtos) > 0 {
		cfg.NextProtos = append([]string(nil), nextProtos...)
	}
	if leaf != nil && len(leaf.DNSNames) == 1 && !strings.Contains(leaf.DNSNames[0], "*") {
		// 只有一个名字时用它做缺省 SNI：客户端不带 SNI（如按 IP 直连）
		// 也能拿到正确的证书，不必依赖客户端的默认行为
		cfg.ServerName = leaf.DNSNames[0]
	}
	return cfg, nil
}

// Info 返回证书摘要，供界面展示
func (m *CertManager) Info() CertInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	info := CertInfo{Source: m.cfg.Source}
	if !m.loaded || m.leaf == nil {
		info.Error = "证书尚未载入"
		if m.loadErr != nil {
			info.Error = m.loadErr.Error()
		}
		return info
	}

	leaf := m.leaf
	info.Loaded = true
	info.Subject = leaf.Subject.String()
	info.Issuer = leaf.Issuer.String()
	info.SerialNumber = strings.ToUpper(leaf.SerialNumber.Text(16))
	info.NotBefore = leaf.NotBefore.Format(time.RFC3339)
	info.NotAfter = leaf.NotAfter.Format(time.RFC3339)
	info.DNSNames = append([]string(nil), leaf.DNSNames...)
	info.ChainLength = len(m.chain)
	info.SelfSigned = isSelfSigned(leaf)
	info.DaysRemaining = int(time.Until(leaf.NotAfter).Hours() / 24)

	ips := make([]string, 0, len(leaf.IPAddresses))
	for _, ip := range leaf.IPAddresses {
		ips = append(ips, ip.String())
	}
	info.IPAddresses = ips

	sum := sha256.Sum256(leaf.Raw)
	info.Fingerprint = formatFingerprint(sum[:])
	return info
}

// EnsureSelfSigned 确保证书目录下存在一张自签证书；已存在则沿用。
//
// 返回 true 表示本次新生成。沿用而不是每次启动都重签，是因为客户端
// （尤其是 iOS 描述文件）会记住已信任的证书，重签等于让它们全部失效。
func (m *CertManager) EnsureSelfSigned(cfg CertConfig) (bool, error) {
	NormalizeCertConfig(&cfg)

	dir := m.Dir()
	if dir == "" {
		return false, fmt.Errorf("证书目录未配置")
	}
	certPath := filepath.Join(dir, SelfSignedCertFileName)
	keyPath := filepath.Join(dir, SelfSignedKeyFileName)

	// 见文件即短路只在「确实是我们自己的自签件」时成立：导入的 PEM 会
	// 被记到 file 来源，此时绝不能把导入证书当成自签再复用（BUG-64）。
	if fileExists(certPath) && fileExists(keyPath) && m.ownedBySelfSigned() {
		m.Configure(cfgSource(cfg, CertSourceSelfSigned))
		return false, nil
	}

	gen, err := GenerateSelfSignedCert(cfg)
	if err != nil {
		return false, err
	}
	if err := writeFilePrivate(certPath, gen.CertPEM); err != nil {
		return false, err
	}
	if err := writeFilePrivate(keyPath, gen.KeyPEM); err != nil {
		return false, err
	}

	m.Configure(cfgSource(cfg, CertSourceSelfSigned))
	return true, nil
}

// ownedBySelfSigned 报告当前配置是否本就指向自签固定文件。
//
// 来源为 file 且路径不是自签固定文件时，磁盘上的 server.crt/key 属于
// 导入件，不能被自签流程复用或覆盖。
func (m *CertManager) ownedBySelfSigned() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if m.cfg.Source == CertSourceSelfSigned || m.cfg.Source == "" {
		return true
	}
	if m.cfg.Source != CertSourceFile {
		return false
	}
	if !sameFilePath(m.cfg.CertFile, filepath.Join(m.dir, SelfSignedCertFileName)) {
		return false
	}
	// 旧版本把导入件也落在 server.crt：只有内容确实是自签证书时才认作己有，
	// 否则仍应重新生成自签件而不是复用那张外部证书。
	return m.leaf != nil && isSelfSigned(m.leaf)
}

// sameFilePath 比较两个文件路径是否指向同一文件（忽略大小写与相对路径差异）。
func sameFilePath(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	if pa, err := filepath.Abs(a); err == nil {
		a = pa
	}
	if pb, err := filepath.Abs(b); err == nil {
		b = pb
	}
	return strings.EqualFold(filepath.Clean(a), filepath.Clean(b))
}

// RegenerateSelfSigned 无条件重新签发一张自签证书。
//
// 与 EnsureSelfSigned 的区别在意图：那个是「保证有证书可用」，这个是
// 「换一张」。重签会让已信任旧证书的客户端（尤其是装了描述文件的手机）
// 全部失效，所以调用方必须显式表达这个意图，而不是靠删文件来触发。
func (m *CertManager) RegenerateSelfSigned(cfg CertConfig) error {
	NormalizeCertConfig(&cfg)

	dir := m.Dir()
	if dir == "" {
		return fmt.Errorf("证书目录未配置")
	}
	gen, err := GenerateSelfSignedCert(cfg)
	if err != nil {
		return err
	}
	if err := writeFilePrivate(filepath.Join(dir, SelfSignedCertFileName), gen.CertPEM); err != nil {
		return err
	}
	if err := writeFilePrivate(filepath.Join(dir, SelfSignedKeyFileName), gen.KeyPEM); err != nil {
		return err
	}

	m.Configure(cfgSource(cfg, CertSourceSelfSigned))
	return nil
}

// ImportPEM 校验并导入一对 PEM 证书/私钥。
//
// 先解析、能配对、再落盘：把一对不匹配的证书与私钥写进证书目录，
// 会在下一次启动时以「TLS 握手失败」的形式暴露，而不是在导入时。
func (m *CertManager) ImportPEM(certPEM, keyPEM []byte) error {
	pair, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		return fmt.Errorf("证书与私钥不匹配或格式无效: %w", err)
	}
	if len(pair.Certificate) == 0 {
		return fmt.Errorf("证书链为空")
	}

	dir := m.Dir()
	if dir == "" {
		return fmt.Errorf("证书目录未配置")
	}
	// 导入件与自签件分开命名：共用一个文件名会让「来源切换」变成
	// 互相踩踏——切回 self_signed 会复用导入件，重签又会覆盖导入件。
	certPath := filepath.Join(dir, ImportedCertFileName)
	keyPath := filepath.Join(dir, ImportedKeyFileName)

	// 落盘的是从已解析的密钥对重新编码的结果，而不是用户交上来的那段
	// 文本：后者可能夹带私钥之外的块或注释，证书目录里只该有我们认得的
	// 那两样东西。
	key, err := x509.MarshalPKCS8PrivateKey(pair.PrivateKey)
	if err != nil {
		return fmt.Errorf("编码私钥失败: %w", err)
	}
	if err := writeFilePrivate(certPath, certPEM); err != nil {
		return err
	}
	if err := writeFilePrivate(keyPath, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: key})); err != nil {
		return err
	}

	// 导入后按文件来源记账，路径必须指到刚落盘的那两个文件上：
	// 留空会让下一次重载去找「配置里写的路径」，而那是空的
	cfg := m.GetConfig()
	cfg.Source = CertSourceFile
	cfg.CertFile = certPath
	cfg.KeyFile = keyPath
	m.Configure(cfg)
	return nil
}

// CurrentPaths 返回当前生效的证书与私钥路径，供持久化 ImportPEM 的落点
func (m *CertManager) CurrentPaths() (certPath, keyPath string) {
	m.mu.RLock()
	cfg, dir := m.cfg, m.dir
	m.mu.RUnlock()

	certPath, keyPath, _, err := resolveCertPaths(dir, cfg)
	if err != nil {
		return "", ""
	}
	return certPath, keyPath
}

// ImportPKCS12 从 PKCS#12 文件导入证书与私钥
func (m *CertManager) ImportPKCS12(pfx []byte, password string) error {
	priv, cert, err := pkcs12.Decode(pfx, password)
	if err != nil {
		return fmt.Errorf("解析 PKCS#12 失败（口令是否正确）: %w", err)
	}
	if priv == nil || cert == nil {
		return fmt.Errorf("PKCS#12 中缺少私钥或证书")
	}

	keyPEM, err := encodePrivateKey(priv)
	if err != nil {
		return err
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
	return m.ImportPEM(certPEM, keyPEM)
}

// loadCertMaterial 按配置从磁盘取回证书与私钥
func loadCertMaterial(dir string, cfg CertConfig) (*tls.Certificate, []*x509.Certificate, error) {
	certPath, keyPath, password, err := resolveCertPaths(dir, cfg)
	if err != nil {
		return nil, nil, err
	}

	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, nil, fmt.Errorf("读取证书失败: %w", err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, nil, fmt.Errorf("读取私钥失败: %w", err)
	}

	if password != "" {
		// PKCS#12 走独立的解析路径：它不是 PEM，X509KeyPair 读不了
		priv, cert, err := pkcs12.Decode(certPEM, password)
		if err != nil {
			return nil, nil, fmt.Errorf("解析 PKCS#12 失败: %w", err)
		}
		keyPEM, err = encodePrivateKey(priv)
		if err != nil {
			return nil, nil, err
		}
		certPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
	}

	pair, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		return nil, nil, fmt.Errorf("证书与私钥不匹配: %w", err)
	}
	chain, err := parseChain(certPEM)
	if err != nil {
		return nil, nil, err
	}
	return &pair, chain, nil
}

// resolveCertPaths 由配置推导证书与私钥的实际路径
func resolveCertPaths(dir string, cfg CertConfig) (certPath, keyPath, password string, err error) {
	if cfg.Source == CertSourceSelfSigned || cfg.Source == "" {
		if dir == "" {
			return "", "", "", fmt.Errorf("证书目录未配置")
		}
		return filepath.Join(dir, SelfSignedCertFileName),
			filepath.Join(dir, SelfSignedKeyFileName), "", nil
	}

	certPath = cfg.CertFile
	if certPath == "" {
		return "", "", "", fmt.Errorf("未指定证书文件路径")
	}
	if cfg.Source == CertSourcePKCS12 {
		// PKCS#12 把证书与私钥装在一个文件里，两者路径相同
		return certPath, certPath, cfg.PKCS12Password, nil
	}
	keyPath = cfg.KeyFile
	if keyPath == "" {
		return "", "", "", fmt.Errorf("未指定私钥文件路径")
	}
	return certPath, keyPath, "", nil
}

// parseChain 解析证书链；首块必须是证书
func parseChain(certPEM []byte) ([]*x509.Certificate, error) {
	var chain []*x509.Certificate
	rest := certPEM
	for {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" {
			continue
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("解析证书链失败: %w", err)
		}
		chain = append(chain, cert)
	}
	if len(chain) == 0 {
		return nil, fmt.Errorf("证书文件中没有可用的 CERTIFICATE 块")
	}
	return chain, nil
}

// cfgSource 返回一份把 Source 改成 src 的配置副本
func cfgSource(cfg CertConfig, src string) CertConfig {
	cfg.Source = src
	return cfg
}

// writeFilePrivate 以 0600 写文件。
//
// 私钥一旦可被同机其他用户读取，这套加密监听就只剩「传输加密」而
// 没有「身份认证」——任何人都能用同一个名字架一台假冒服务器。
func writeFilePrivate(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("创建证书目录失败: %w", err)
	}
	// 目录也要收紧：Windows 下 0o700 不产生任何 ACL 效果，
	// 新建文件会继承父目录（%ProgramData%\DITING）默认的 Users 读权限。
	hardenPrivatePath(dir)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("写入 %s 失败: %w", filepath.Base(path), err)
	}
	// 补一次显式 Chmod：目标文件已存在时 WriteFile 不会收紧原有权限，
	// 一个早先以 0644 落盘、之后被覆盖的私钥会一直保持可读。
	// 失败不算致命——文件已写入，收紧权限只是加固。
	_ = os.Chmod(path, 0o600)
	hardenPrivatePath(path)
	return nil
}

// hardenPrivatePath 在支持 ACL 的平台上把路径收紧为仅系统/管理员可访问。
//
// 其它平台是空操作：POSIX 下权限已由 mode 表达。失败只记录，
// 不阻断证书落盘——没有证书整个加密监听都起不来，比权限放宽更糟。
func hardenPrivatePath(path string) {
	if err := protect.ProtectPathPrivate(path); err != nil {
		log.Printf("收紧 %s 访问权限失败: %v", path, err)
	}
}

// fileExists 判断常规文件是否存在
func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// formatFingerprint 把摘要格式化成冒号分隔的大写十六进制
func formatFingerprint(sum []byte) string {
	parts := make([]string, 0, len(sum))
	for _, b := range sum {
		parts = append(parts, strings.ToUpper(hex.EncodeToString([]byte{b})))
	}
	return strings.Join(parts, ":")
}
