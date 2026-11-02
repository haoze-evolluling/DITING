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

func TestCosmeticCssScopesRulesByHost(t *testing.T) {
	example := buildCosmeticCss(cosmeticFixture, "www.example.com")
	if !strings.Contains(example, ".banner-ad { display: none !important; }") {
		t.Fatalf("scoped rule missing for subdomain: %q", example)
	}
	if !strings.Contains(example, ".generic-ad { display: none !important; }") {
		t.Fatalf("global rule missing: %q", example)
	}

	unrelated := buildCosmeticCss(cosmeticFixture, "unrelated.org")
	if strings.Contains(unrelated, ".banner-ad") {
		t.Fatalf("example.com rule leaked to unrelated.org: %q", unrelated)
	}
	if !strings.Contains(unrelated, ".generic-ad") {
		t.Fatalf("global rule must still apply: %q", unrelated)
	}
}

func TestCosmeticCssAppliesExceptionInsteadOfHide(t *testing.T) {
	css := buildCosmeticCss(cosmeticFixture, "example.com")
	if strings.Contains(css, ".site-banner { display: none") {
		t.Fatalf("exception compiled as hide: %q", css)
	}
	if !strings.Contains(css, ".site-banner { display: revert !important; }") {
		t.Fatalf("exception override missing: %q", css)
	}
}

// A `#@#` rule with no domain scope reaches the engine as globalException.
// It used to be counted (map sized) but never copied in, so a global hide could
// never be un-hidden on any site.
const cosmeticGlobalExceptionFixture = `{
  "globalHide": [".generic-ad", ".promo"],
  "globalException": [".generic-ad"],
  "domains": {
    "example.com": {"hide": [".banner-ad"], "exception": []}
  }
}`

func TestCosmeticCssAppliesGlobalException(t *testing.T) {
	css := buildCosmeticCss(cosmeticGlobalExceptionFixture, "unrelated.org")
	if strings.Contains(css, ".generic-ad { display: none") {
		t.Fatalf("globally excepted selector still hidden: %q", css)
	}
	if !strings.Contains(css, ".generic-ad { display: revert !important; }") {
		t.Fatalf("global exception override missing: %q", css)
	}
	if !strings.Contains(css, ".promo { display: none !important; }") {
		t.Fatalf("unrelated global hide must survive: %q", css)
	}

	// A host-scoped hide of the same selector must also lose to the global
	// exception, because the exception is applied after the host walk.
	scoped := buildCosmeticCss(cosmeticGlobalExceptionFixture, "example.com")
	if strings.Contains(scoped, ".generic-ad { display: none") {
		t.Fatalf("global exception did not override host hide: %q", scoped)
	}
}

func TestCosmeticCssEmptyPayload(t *testing.T) {
	if got := buildCosmeticCss("", "example.com"); !strings.Contains(got, "no cosmetic rules") {
		t.Fatalf("unexpected stylesheet for empty payload: %q", got)
	}
}

func TestCosmeticLinkTagCarriesHost(t *testing.T) {
	tag := cosmeticLinkTag("Ads.Example.com:443")
	want := `href="https://local.pwhs.app/cosmetic.css?h=ads.example.com"`
	if !strings.Contains(tag, want) {
		t.Fatalf("link tag %q does not contain %q", tag, want)
	}
	if strings.Contains(tag, "?h=") && strings.Contains(cosmeticLinkTag(""), "?h=") {
		t.Fatalf("host-less tag must not carry a query")
	}
}

func TestServeCssUsesRequestHost(t *testing.T) {
	SetCosmeticRules(cosmeticFixture)
	defer SetCosmeticRules("")

	req, err := http.NewRequest("GET", "https://local.pwhs.app/cosmetic.css?h=example.com", nil)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(ServeLocalAsset(req).Body)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(body), ".banner-ad { display: none !important; }") {
		t.Fatalf("served css missing host-scoped rule: %q", string(body))
	}

	otherReq, _ := http.NewRequest("GET", "https://local.pwhs.app/cosmetic.css?h=other.org", nil)
	otherBody, err := io.ReadAll(ServeLocalAsset(otherReq).Body)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(otherBody), ".banner-ad") {
		t.Fatalf("served css leaked a scoped rule: %q", string(otherBody))
	}
}

func TestInjectedResponseIsSelfDelimiting(t *testing.T) {
	SetCosmeticRules(cosmeticFixture)
	defer SetCosmeticRules("")

	const raw = "HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html; charset=utf-8\r\n" +
		"Content-Length: 46\r\n" +
		"\r\n" +
		"<html><head><title>t</title></head><body>x</body></html>"

	resp := readUpstreamResponse(t, raw, "GET")
	if !ShouldInjectHTML(resp.Header.Get("Content-Type")) {
		t.Fatal("fixture must be treated as injectable HTML")
	}
	wrapResponseForInjection(resp, "example.com")

	wire := serializeResponse(t, resp)

	head, body, found := strings.Cut(string(wire), "\r\n\r\n")
	if !found {
		t.Fatalf("no header/body separator in %q", wire)
	}
	lowerHead := strings.ToLower(head)
	closeDelimited := strings.Contains(lowerHead, "connection: close")
	chunked := strings.Contains(lowerHead, "transfer-encoding: chunked")
	hasContentLength := strings.Contains(lowerHead, "content-length:")
	if !closeDelimited && !chunked && !hasContentLength {
		t.Fatalf("injected response has no body boundary (keep-alive client would hang); headers: %q", head)
	}
	if !strings.Contains(body, "cosmetic.css") {
		t.Fatalf("injection missing from body: %q", body)
	}
	if resp.Close != true {
		t.Fatal("relay only closes the connection on resp.Close, so it must be set")
	}
}

// A HEAD response has no body at all, but the injected variant used to lose its
// Content-Length as well, leaving the client with nothing to size the response by.
func TestInjectedHeadResponseKeepsFraming(t *testing.T) {
	SetCosmeticRules(cosmeticFixture)
	defer SetCosmeticRules("")

	const raw = "HTTP/1.1 200 OK\r\n" +
		"Content-Type: text/html; charset=utf-8\r\n" +
		"Content-Length: 46\r\n" +
		"\r\n"

	resp := readUpstreamResponse(t, raw, "HEAD")
	wrapResponseForInjection(resp, "example.com")
	wire := serializeResponse(t, resp)

	head := string(wire)
	if !strings.Contains(strings.ToLower(head), "connection: close") &&
		!strings.Contains(strings.ToLower(head), "content-length:") {
		t.Fatalf("HEAD response lost its framing: %q", head)
	}
}

// Injection must stay streaming: a large body may not be buffered just to compute
// a Content-Length, so the reader has to yield the injected tag while the upstream
// body is still being produced.
func TestInjectionStreamsWithoutBufferingWholeBody(t *testing.T) {
	SetCosmeticRules(cosmeticFixture)
	defer SetCosmeticRules("")

	upstream := io.MultiReader(
		strings.NewReader("<html><head>"),
		&countingReader{remaining: 4 << 20},
	)
	reader := NewInjectingReader(upstream, "example.com")
	out, err := io.ReadAll(io.LimitReader(reader, 4096))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !strings.Contains(string(out), "cosmetic.css") {
		t.Fatalf("injection did not stream: %q", string(out[:min(len(out), 200)]))
	}
}
