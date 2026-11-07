// mitm_cosmetic_inject.go provides streaming HTML rewriting for cosmetic ad-blocking CSS injection.
//
// Injection Architecture:
// - Scans the uncompressed response stream for <head> tags (case-insensitive) using a sliding buffer.
// - Injects a lightweight <link rel="stylesheet"> pointing to the in-memory asset host (local.pwhs.app),
//   avoiding inline injection of 50-100KB CSS payloads and enabling client browser caching.
// - The stylesheet URL carries the page hostname (`/cosmetic.css?h=<host>`), so the local asset server
//   can serve the subset of rules scoped to that host plus `#@#` exceptions.
//
// Responsibility split: the scanner, the hostname normalization and the `<link>` tag live in the Rust
// kernel `rust/diting-cosmetic-core` (see mitm_cosmetic_native.go). Go keeps the rule payload, the
// `io.ReadCloser` the relay hands to net/http, and the log lines. There is no second scanner here.

package tunnel

import (
	"io"
	"strings"
	"sync"
)

var (
	cosmeticMu  sync.RWMutex
	cosmeticCSS string
)

// SetCosmeticRules replaces the scoped cosmetic rule set.
//
// The payload is JSON of the shape:
//
//	{"globalHide":["sel"],"globalException":["sel"],
//	 "domains":{"example.com":{"hide":["sel"],"exception":["sel"]}}}
//
// so rule matching happens per inspected hostname instead of applying every
// rule to every site. An empty string disables injection.
func SetCosmeticRules(payload string) {
	cosmeticMu.Lock()
	cosmeticCSS = payload
	cosmeticMu.Unlock()
	logf("Cosmetic rules updated: %d bytes", len(payload))
}

func cosmeticRulesEmpty() bool {
	cosmeticMu.RLock()
	defer cosmeticMu.RUnlock()
	return strings.TrimSpace(cosmeticCSS) == ""
}

// ShouldInjectHTML reports whether a response body is a page worth rewriting.
//
// This stays in Go: `strings.Contains(strings.ToLower(ct), "text/html")` needs no state, and the
// kernel would only add an error path to a predicate the relay asks once per response.
func ShouldInjectHTML(contentType string) bool {
	ct := strings.ToLower(contentType)
	return strings.Contains(ct, "text/html")
}

// normalizeCosmeticHost lowercases the host, drops any port and strips the trailing root label so it
// matches the stored rule domains.
//
// The local asset server serves `?h=<host>`, so this is the same normalization the injected link
// carries; it lives in the kernel and is only wrapped here. A failure (the kernel is loaded by
// StartStackMitm, so this is unreachable once interception runs) leaves the stylesheet unscoped.
func normalizeCosmeticHost(host string) string {
	normalized, err := cosmeticNativeNormalizeHost(host)
	if err != nil {
		logf("MITM: cosmetic kernel cannot normalize host %q: %v", host, err)
		return ""
	}
	return normalized
}

// cosmeticLinkTag builds the stylesheet tag for one page hostname.
//
// The hostname normalization (`net.SplitHostPort` shape rules, `url.QueryEscape`) happens in the
// kernel so the tag cannot drift from the rules it is looked up against.
func cosmeticLinkTag(host string) (string, error) {
	return cosmeticNativeLinkTag(host)
}

// injectingReader splices the `<link>` tag into the upstream body as it streams.
//
// The scanner state (carry, pending, the 16 KiB scan limit) lives in the kernel; this type only
// shuffles bytes between net/http and the handle, and frees the handle when the body is closed.
type injectingReader struct {
	upstream io.Reader
	kernel   *cosmeticKernel
	// err is set when the kernel could not be loaded; the first Read reports it instead of
	// serving the page un-injected.
	err error
}

// NewInjectingReader wraps upstream so the cosmetic stylesheet link is spliced in after `<head>`.
//
// The caller owns the returned reader and must close it: that is what frees the kernel handle.
func NewInjectingReader(upstream io.Reader, host string) io.ReadCloser {
	reader := &injectingReader{upstream: upstream}
	if err := ensureCosmeticKernel(); err != nil {
		reader.err = err
		return reader
	}
	tag, err := cosmeticLinkTag(host)
	if err != nil {
		reader.err = err
		return reader
	}
	kernel, err := newCosmeticKernel(tag)
	if err != nil {
		reader.err = err
		return reader
	}
	reader.kernel = kernel
	return reader
}

func (r *injectingReader) Read(p []byte) (int, error) {
	if r.err != nil {
		return 0, r.err
	}
	// The kernel holds back a partial `<head` marker and the bytes a splice did not fit; it serves
	// those before the upstream is asked for more.
	if n := r.kernel.pending(p); n > 0 {
		return n, nil
	}
	n, err := r.upstream.Read(p)
	return r.kernel.process(p, n, err)
}

// Close frees the scanner and, when the upstream can be closed, closes it too.
func (r *injectingReader) Close() error {
	if r.kernel != nil {
		r.kernel.free()
		r.kernel = nil
	}
	if closer, ok := r.upstream.(io.Closer); ok {
		return closer.Close()
	}
	return nil
}
