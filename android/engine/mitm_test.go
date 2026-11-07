// mitm_test.go covers the MITM data path: upstream root trust, the
// domain-scoped cosmetic stylesheet, and the framing of injected responses.
//
// A cosmetic rule scoped to one domain must not leak to other sites, #@# must
// un-hide a selector, and the rewritten response must still tell the client
// where the body ends (Connection: close, chunked or Content-Length). Without
// that an HTTP/1.1 keep-alive client waits for a boundary that never arrives.

package tunnel

import (
	"bufio"
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/pem"
	"io"
	"math/big"
	"net/http"
	"strings"
	"testing"
	"time"
)

// readUpstreamResponse parses a raw HTTP/1.1 response the same way the relay
// does, so the test exercises the real *http.Response the injection rewrites.
func readUpstreamResponse(t *testing.T, raw string, method string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(method, "http://example.com/page", nil)
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	resp, err := http.ReadResponse(bufio.NewReader(strings.NewReader(raw)), req)
	if err != nil {
		t.Fatalf("read response: %v", err)
	}
	return resp
}

type countingReader struct{ remaining int }

func (c *countingReader) Read(p []byte) (int, error) {
	if c.remaining <= 0 {
		return 0, io.EOF
	}
	n := len(p)
	if n > c.remaining {
		n = c.remaining
	}
	for i := 0; i < n; i++ {
		p[i] = 'x'
	}
	c.remaining -= n
	return n, nil
}

func TestBundledRootsParse(t *testing.T) {
	for name, pemStr := range map[string]string{
		"ISRG Root X1": isrgRootX1PEM,
		"ISRG Root X2": isrgRootX2PEM,
	} {
		block, _ := pem.Decode([]byte(pemStr))
		if block == nil {
			t.Fatalf("%s: no PEM block decoded", name)
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			t.Fatalf("%s: parse: %v", name, err)
		}
		if !cert.IsCA {
			t.Errorf("%s: expected IsCA=true", name)
		}
		if time.Now().After(cert.NotAfter) {
			t.Errorf("%s: bundled root is expired (NotAfter=%s)", name, cert.NotAfter)
		}
	}
}

func TestUpstreamRootPoolIncludesBundled(t *testing.T) {
	pool, added := buildUpstreamRootPool()
	if pool == nil {
		t.Fatal("buildUpstreamRootPool returned nil pool")
	}
	if added != 2 {
		t.Errorf("expected both bundled ISRG roots appended to pool, got %d", added)
	}

	if upstreamRootPool() == nil {
		t.Error("upstreamRootPool returned nil")
	}
}

func TestIsExtendedValidation(t *testing.T) {
	mk := func(policies []asn1.ObjectIdentifier) *x509.Certificate {
		key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		tmpl := &x509.Certificate{
			SerialNumber:      big.NewInt(1),
			Subject:           pkix.Name{CommonName: "example.com"},
			NotBefore:         time.Now().Add(-time.Hour),
			NotAfter:          time.Now().Add(time.Hour),
			PolicyIdentifiers: policies,
		}
		der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
		if err != nil {
			t.Fatalf("create cert: %v", err)
		}
		c, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatalf("parse cert: %v", err)
		}
		return c
	}

	ev := mk([]asn1.ObjectIdentifier{{2, 23, 140, 1, 1}})
	if !isExtendedValidation(ev) {
		t.Error("expected EV cert to be detected")
	}

	dv := mk([]asn1.ObjectIdentifier{{2, 23, 140, 1, 2, 1}})
	if isExtendedValidation(dv) {
		t.Error("DV cert should not be flagged EV")
	}

	if isExtendedValidation(nil) {
		t.Error("nil cert should not be flagged EV")
	}
}

// serializeResponse writes resp to a buffer and returns the raw bytes, which is
// exactly what relayHTTPFlow hands to the client connection.
func serializeResponse(t *testing.T, resp *http.Response) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := resp.Write(&buf); err != nil {
		t.Fatalf("write response: %v", err)
	}
	return buf.Bytes()
}

const cosmeticFixture = `{
  "globalHide": [".generic-ad"],
  "globalException": [],
  "domains": {
    "example.com": {"hide": [".banner-ad", ".generic-ad"], "exception": [".site-banner"]},
    "other.com": {"hide": [".banner-ad"], "exception": []},
    "site-banner": {"hide": [".site-banner"], "exception": []}
  }
}`
