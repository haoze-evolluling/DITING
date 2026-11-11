package core

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"net"
	"strings"
	"testing"
	"time"
)

func TestParseCertPin(t *testing.T) {
	canonical := strings.Repeat("ab", 32)

	pin, err := ParseCertPin(canonical)
	if err != nil {
		t.Fatalf("ParseCertPin: %v", err)
	}
	if len(pin.Sha256) != sha256.Size {
		t.Fatalf("pin length = %d", len(pin.Sha256))
	}

	// 冒号、空格、连字符与大小写差异都必须等价
	for _, variant := range []string{
		strings.Repeat("AB:", 31) + "AB",
		strings.Repeat("ab ", 32),
		strings.Repeat("ab-", 31) + "ab",
		"  " + canonical + "  ",
	} {
		other, err := ParseCertPin(variant)
		if err != nil {
			t.Fatalf("ParseCertPin(%q): %v", variant, err)
		}
		if !equalBytes(other.Sha256, pin.Sha256) {
			t.Fatalf("variant %q decoded differently", variant)
		}
	}
}

func TestParseCertPin_Errors(t *testing.T) {
	cases := map[string]string{
		"empty":          "",
		"whitespace":     "   ",
		"bad hex":        "zz",
		"too short":      strings.Repeat("ab", 16),
		"too long":       strings.Repeat("ab", 64),
		"odd length hex": strings.Repeat("a", 63),
	}
	for name, in := range cases {
		if _, err := ParseCertPin(in); err == nil {
			t.Errorf("%s: expected error, got nil", name)
		}
	}
}

func TestCertPinHex(t *testing.T) {
	pin, _ := CertPinFromRaw([]byte{0x00, 0x01, 0xAB, 0xFF})
	var nilPin *CertPin
	if got := nilPin.Hex(); got != "" {
		t.Fatalf("nil pin Hex() = %q", got)
	}

	_ = pin // 4 字节不合法，考察空值路径即可
	if _, err := CertPinFromRaw([]byte{0x00}); err == nil {
		t.Fatal("expected error for short pin")
	}
}

func TestPinAwareTLSConfig_NilLookupPassthrough(t *testing.T) {
	base := &tls.Config{ServerName: "example.com"}

	cfg := PinAwareTLSConfig(base, nil)
	if cfg.InsecureSkipVerify {
		t.Fatal("nil lookup must not disable verification")
	}
	if cfg.VerifyConnection != nil {
		t.Fatal("nil lookup must not install a verification hook")
	}
	if cfg.ServerName != "example.com" {
		t.Fatalf("server name = %q", cfg.ServerName)
	}

	// lookup 是按主机名分派的，配置期无法预知将被询问哪些主机，
	// 因此只要 lookup 非空就会安装钩子；关键在于未命中指纹的主机
	// 仍走标准链校验，而不是被放行。
	lookup := func(host string) *CertPin { return nil }
	cfg = PinAwareTLSConfig(base, lookup)
	if cfg.VerifyConnection == nil {
		t.Fatal("non-nil lookup must install the dispatching hook")
	}
}

func TestPinAwareTLSConfig_InstallsHookOnlyWhenPinned(t *testing.T) {
	pin, _ := CertPinFromRaw(make([]byte, 32))
	lookup := func(host string) *CertPin {
		if host == "pinned.example.com" {
			return pin
		}
		return nil
	}

	cfg := PinAwareTLSConfig(&tls.Config{}, lookup)
	if !cfg.InsecureSkipVerify {
		t.Fatal("pinned config must take over verification")
	}
	if cfg.VerifyConnection == nil {
		t.Fatal("pinned config must install VerifyConnection")
	}
}

func TestPinAwareTLSConfig_RespectsCallerVerification(t *testing.T) {
	// 调用方已自行接管校验时不得叠加，避免覆盖其意图
	base := &tls.Config{InsecureSkipVerify: true}
	pin, _ := CertPinFromRaw(make([]byte, 32))
	cfg := PinAwareTLSConfig(base, func(string) *CertPin { return pin })
	if cfg.VerifyConnection != nil {
		t.Fatal("must not override caller's own verification setup")
	}
}

// TestPinnedTLSConfig_UnpinnedHostStillChainVerified 验证未命中指纹的主机
// 依旧受系统 CA 链校验约束：面对自签证书必须拒绝，而不是被放行。
func TestPinnedTLSConfig_UnpinnedHostStillChainVerified(t *testing.T) {
	cert := generateTestTLSCert(t)
	listener, addr := startMockDoTServerWithCert(t, cert)
	defer listener.Close()

	// 固定表只覆盖别的主机，目标主机未配置指纹
	otherPin, _ := CertPinFromRaw(make([]byte, 32))
	lookup := func(host string) *CertPin {
		if host == "pinned.elsewhere" {
			return otherPin
		}
		return nil
	}

	dot := NewDoTResolver(nil)
	defer dot.Close()
	dot.SetTLSConfig(PinAwareTLSConfig(nil, lookup))

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// 自签证书不在系统 CA 内，未固定该主机时握手必须失败
	if _, err := dot.Exchange(ctx, makeTestDNSQuery("unpinned.example.com"), addr); err == nil {
		t.Fatal("unpinned host must still fail standard chain verification for a self-signed cert")
	}
}

// TestPinnedTLSConfig_EndToEnd 用本地自签名 DoT 服务端验证：
// 指纹正确则握手成功，指纹错误则必须失败。
func TestPinnedTLSConfig_EndToEnd(t *testing.T) {
	cert := generateTestTLSCert(t)

	// 计算服务端证书的 SHA-256(RawTBSCertificate)
	leaf, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}
	sum := sha256.Sum256(leaf.RawTBSCertificate)
	goodPin, err := CertPinFromRaw(sum[:])
	if err != nil {
		t.Fatalf("CertPinFromRaw: %v", err)
	}
	badPin, _ := CertPinFromRaw(make([]byte, 32))

	listener, addr := startMockDoTServerWithCert(t, cert)
	defer listener.Close()

	dialAndQuery := func(pin *CertPin) error {
		dot := NewDoTResolver(nil)
		defer dot.Close()

		// 以固定指纹接管校验（自签证书不经系统 CA，正是固定的典型用途）
		dot.SetTLSConfig(PinnedTestTLSConfig(pin))

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_, err := dot.Exchange(ctx, makeTestDNSQuery("pin.example.com"), addr)
		return err
	}

	if err := dialAndQuery(goodPin); err != nil {
		t.Fatalf("handshake with correct pin must succeed, got: %v", err)
	}

	if err := dialAndQuery(badPin); err == nil {
		t.Fatal("handshake with wrong pin must fail")
	}
}

// PinnedTestTLSConfig 构造仅校验指定指纹的测试 TLS 配置
func PinnedTestTLSConfig(pin *CertPin) *tls.Config {
	lookup := func(string) *CertPin { return pin }
	return PinAwareTLSConfig(nil, lookup)
}

// startMockDoTServerWithCert 用给定证书启动 DoT 假服务端，
// 复用 resolver_dot_test.go 中的 handleDoTConn 处理逻辑。
func startMockDoTServerWithCert(t *testing.T, cert tls.Certificate) (net.Listener, string) {
	t.Helper()

	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{
		Certificates: []tls.Certificate{cert},
	})
	if err != nil {
		t.Fatalf("listen mock dot: %v", err)
	}

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go handleDoTConn(conn)
		}
	}()

	return listener, listener.Addr().String()
}
