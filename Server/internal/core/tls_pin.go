package core

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

// CertPin 表示一个上游服务器的证书固定（certificate pinning）指纹。
//
// 指纹算法为 SHA-256(RawTBSCertificate)，与 DNS Stamps 规范及
// dnscrypt-proxy 的 go-dnsstamps 实现一致：只覆盖 TBSCertificate，
// 因此不受签名算法影响，换链（重新签名）也不会改变指纹。
type CertPin struct {
	Sha256 []byte
}

// Hex 返回冒号分隔的大写十六进制表示，便于展示与比对
func (p *CertPin) Hex() string {
	if p == nil || len(p.Sha256) == 0 {
		return ""
	}
	parts := make([]string, len(p.Sha256))
	for i, b := range p.Sha256 {
		parts[i] = fmt.Sprintf("%02X", b)
	}
	return strings.Join(parts, ":")
}

// String 实现 fmt.Stringer
func (p *CertPin) String() string { return p.Hex() }

// ParseCertPin 解析十六进制证书指纹。
//
// 容忍常见的书写差异：允许冒号、空格或连字符作为分隔符，
// 允许大小写混用，也接受不带分隔符的连续十六进制串。
func ParseCertPin(s string) (*CertPin, error) {
	cleaned := strings.Map(func(r rune) rune {
		switch r {
		case ':', ' ', '-', '\t':
			return -1
		default:
			return r
		}
	}, strings.TrimSpace(s))
	if cleaned == "" {
		return nil, errors.New("empty certificate pin")
	}

	raw, err := hex.DecodeString(cleaned)
	if err != nil {
		return nil, fmt.Errorf("invalid certificate pin hex: %w", err)
	}
	return CertPinFromRaw(raw)
}

// CertPinFromRaw 从原始字节构造指纹（供印章解析使用）
func CertPinFromRaw(raw []byte) (*CertPin, error) {
	if len(raw) != sha256.Size {
		return nil, fmt.Errorf("certificate pin must be %d bytes (SHA-256), got %d", sha256.Size, len(raw))
	}
	pin := &CertPin{Sha256: make([]byte, sha256.Size)}
	copy(pin.Sha256, raw)
	return pin, nil
}

// PinLookup 按主机名查询期望的证书指纹，未配置固定时返回 nil
type PinLookup func(host string) *CertPin

// PinAwareTLSConfig 让一份共享的 TLS 配置支持按主机名区分的证书固定。
//
// 为什么不能简单地在配置上写死一个指纹：同一份 TLS 配置会被多个上游复用，
// 而指纹是每个上游各自的，因此必须在握手时按实际 ServerName 分派。
//
// 安全语义（重要）：
//   - lookup 为 nil（未配置任何指纹）时，原样返回 base，行为与从前完全一致。
//   - 存在指纹时，才接管校验：置 InsecureSkipVerify 并改用 VerifyConnection，
//     因为 Go 的证书链校验一旦被绕过，就必须由我们自己补齐。
//   - 命中指纹 → 只比对该指纹（这正是固定机制的本意：信任自签/私有 CA 部署）。
//   - 未命中指纹 → 回落到标准系统 CA 链校验，**不会**因为别的上游配了固定
//     就放宽这个上游的校验。
func PinAwareTLSConfig(base *tls.Config, lookup PinLookup) *tls.Config {
	var cfg *tls.Config
	if base != nil {
		cfg = base.Clone()
	} else {
		cfg = &tls.Config{}
	}
	if lookup == nil {
		return cfg
	}

	// 若 base 已自带校验回调（例如测试注入的自签名根），不再叠加，避免覆盖调用方意图
	if cfg.InsecureSkipVerify || cfg.VerifyConnection != nil {
		return cfg
	}

	cfg.InsecureSkipVerify = true
	cfg.VerifyConnection = func(cs tls.ConnectionState) error {
		if pin := lookup(cs.ServerName); pin != nil && len(pin.Sha256) > 0 {
			return verifyCertPin(cs.PeerCertificates, pin)
		}
		return verifyStandardChain(cs.PeerCertificates, cs.ServerName)
	}
	return cfg
}

// verifyCertPin 校验对端证书链中是否存在与固定指纹匹配的证书
func verifyCertPin(certs []*x509.Certificate, pin *CertPin) error {
	if len(certs) == 0 {
		return errors.New("pinned upstream presented no certificate")
	}
	wanted := pin.Sha256
	for _, cert := range certs {
		if cert == nil {
			continue
		}
		sum := sha256.Sum256(cert.RawTBSCertificate)
		if equalBytes(sum[:], wanted) {
			return nil
		}
	}
	return fmt.Errorf("certificate pin mismatch: no presented certificate matches %s", pin.Hex())
}

// verifyStandardChain 在接管校验后补齐标准证书链与主机名校验
func verifyStandardChain(certs []*x509.Certificate, serverName string) error {
	if len(certs) == 0 {
		return errors.New("upstream presented no certificate")
	}

	opts := x509.VerifyOptions{
		Intermediates: x509.NewCertPool(),
	}
	// ServerName 为空时不做名称匹配（例如调用方另行指定了校验名）
	if serverName != "" {
		opts.DNSName = serverName
	}
	for _, cert := range certs[1:] {
		opts.Intermediates.AddCert(cert)
	}

	_, err := certs[0].Verify(opts)
	return err
}

func equalBytes(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}
