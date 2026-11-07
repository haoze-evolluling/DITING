//go:build cgo

// mitm_cosmetic_native_test.go covers the cosmetic injection path through rust/diting-cosmetic-core.
//
// These cases need the kernel: the streaming scanner, the hostname normalization and the `<link>`
// tag all live there now, so `go test` on a machine without a C toolchain builds them out (see
// mitm_cosmetic_native_stub.go). The payload decoding and the loader probes below pin the boundary
// itself, the rest are the assertions that used to run against the pure Go implementation.

package tunnel

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

// --- boundary ---------------------------------------------------------------

// TestNormalizeCosmeticHostMatchesTheKernel pins the cases the corpus in
// rust/diting-cosmetic-core/tests/fixtures/host.tsv was built from.
func TestNormalizeCosmeticHostMatchesTheKernel(t *testing.T) {
	cases := map[string]string{
		"Ads.Example.com:443":  "ads.example.com",
		"EXAMPLE.COM.:443":     "example.com",
		"[::1]:443":            "[::1]",
		"[fe80::1%25eth0]:443": "[fe80::1%25eth0]",
		" sp ace.com:1":        "sp ace.com",
		"host:port:extra":      "host:port:extra",
		"user@host:1":          "user@host",
		".":                    "",
	}
	for host, want := range cases {
		if got := normalizeCosmeticHost(host); got != want {
			t.Fatalf("normalize %q = %q, want %q", host, got, want)
		}
	}
}

func TestInjectingReaderClosesTheKernel(t *testing.T) {
	reader := NewInjectingReader(strings.NewReader("<html><head><body>x"), "example.com")
	body, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !strings.Contains(string(body), "cosmetic.css") {
		t.Fatalf("no injection: %q", body)
	}
	if err := reader.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	if injecting, ok := reader.(*injectingReader); ok && injecting.kernel != nil {
		t.Fatal("close left the kernel handle behind")
	}
}

// --- the assertions that used to run against the Go implementation ----------

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
	tag, err := cosmeticLinkTag("Ads.Example.com:443")
	if err != nil {
		t.Fatalf("link tag: %v", err)
	}
	want := `href="https://local.pwhs.app/cosmetic.css?h=ads.example.com"`
	if !strings.Contains(tag, want) {
		t.Fatalf("link tag %q does not contain %q", tag, want)
	}
	hostless, err := cosmeticLinkTag("")
	if err != nil {
		t.Fatalf("host-less link tag: %v", err)
	}
	if strings.Contains(tag, "?h=") && strings.Contains(hostless, "?h=") {
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

// --- A-064: InjectingReader must flush carry at EOF ------------------------

func TestInjectingReaderFlushesPartialHeadAtEOF(t *testing.T) {
	// The document ends in a bare `<head` with no `>`. The reader parks it in
	// carry hoping the next read completes the tag; at EOF those bytes are still
	// part of the document and used to be dropped.
	const body = "<html><body><head"
	got, err := io.ReadAll(NewInjectingReader(strings.NewReader(body), "example.com"))
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if string(got) != body {
		t.Fatalf("carry was dropped at EOF: got %q, want %q", string(got), body)
	}
}

func TestInjectingReaderInjectsWhenHeadIsComplete(t *testing.T) {
	const body = "<html><head><title>t</title></head><body>x</body></html>"
	out, err := io.ReadAll(NewInjectingReader(strings.NewReader(body), "example.com"))
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if !strings.Contains(string(out), `rel="stylesheet"`) {
		t.Fatalf("stylesheet link was not injected: %q", string(out))
	}
	if !strings.Contains(string(out), "<title>t</title>") {
		t.Fatalf("document body was damaged: %q", string(out))
	}
}

func TestInjectingReaderPassthroughWhenNoHead(t *testing.T) {
	const body = "<html><body>no head here at all</body></html>"
	out, err := io.ReadAll(NewInjectingReader(strings.NewReader(body), "example.com"))
	if err != nil {
		t.Fatalf("read failed: %v", err)
	}
	if string(out) != body {
		t.Fatalf("document was altered: got %q, want %q", string(out), body)
	}
}
