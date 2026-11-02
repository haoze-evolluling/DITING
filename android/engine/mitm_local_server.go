// mitm_local_server.go implements the embedded HTTP server serving cached ad-blocking cosmetic assets.
//
// Caching & Performance:
// - Serves in-memory CSS/JS assets for the local asset hostname (local.pwhs.app).
// - Generates deterministic ETags to support HTTP 304 Not Modified responses, minimizing mobile browser overhead.

package tunnel

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"
)

const LocalAssetHost = "local.pwhs.app"

// cosmeticRuleSet mirrors the JSON pushed from Kotlin (CosmeticRuleManager).
type cosmeticRuleSet struct {
	GlobalHide      []string                       `json:"globalHide"`
	GlobalException []string                       `json:"globalException"`
	Domains         map[string]cosmeticDomainRules `json:"domains"`
}

type cosmeticDomainRules struct {
	Hide      []string `json:"hide"`
	Exception []string `json:"exception"`
}

func ServeLocalAsset(req *http.Request) *http.Response {
	path := req.URL.Path

	switch {
	case path == "/cosmetic.css":
		return serveCSS(req)
	case path == "/health":
		return serveHealth(req)
	default:
		return serve404(req)
	}
}

// buildCosmeticCss renders the stylesheet for one page hostname.
//
// Hide rules apply to the host and all of its subdomains; `#@#` exceptions on
// a host (or any parent domain) remove the selector from the hide set and emit
// a `display: revert` override so a more specific rule cannot win.
func buildCosmeticCss(payload, host string) string {
	trimmed := strings.TrimSpace(payload)
	if trimmed == "" {
		return "/* DITING: no cosmetic rules loaded */"
	}

	var rules cosmeticRuleSet
	if err := json.Unmarshal([]byte(trimmed), &rules); err != nil {
		return "/* DITING: invalid cosmetic rules */"
	}

	hide := make(map[string]struct{}, len(rules.GlobalHide))
	for _, selector := range rules.GlobalHide {
		hide[selector] = struct{}{}
	}
	exceptions := make(map[string]struct{}, len(rules.GlobalException))
	// `#@#` rules without a domain scope arrive as globalException. They must
	// un-hide a selector for every host, otherwise a global hide wins forever.
	for _, selector := range rules.GlobalException {
		exceptions[selector] = struct{}{}
	}

	// Walk from the page host down to its parents, so a rule scoped to
	// `example.com` also applies on `ads.example.com`.
	for _, domain := range hostSuffixes(host) {
		entry, ok := rules.Domains[domain]
		if !ok {
			continue
		}
		for _, selector := range entry.Hide {
			hide[selector] = struct{}{}
		}
		for _, selector := range entry.Exception {
			exceptions[selector] = struct{}{}
		}
	}

	hidden := make([]string, 0, len(hide))
	for selector := range hide {
		if _, excepted := exceptions[selector]; excepted {
			continue
		}
		hidden = append(hidden, selector)
	}
	sort.Strings(hidden)

	excepted := make([]string, 0, len(exceptions))
	for selector := range exceptions {
		excepted = append(excepted, selector)
	}
	sort.Strings(excepted)

	var sb strings.Builder
	for _, selector := range hidden {
		sb.WriteString(selector)
		sb.WriteString(" { display: none !important; }\n")
	}
	for _, selector := range excepted {
		sb.WriteString(selector)
		sb.WriteString(" { display: revert !important; }\n")
	}
	return sb.String()
}

// hostSuffixes returns the host followed by each parent domain, e.g.
// ["ads.example.com", "example.com", "com"].
func hostSuffixes(host string) []string {
	h := normalizeCosmeticHost(host)
	if h == "" {
		return nil
	}
	suffixes := []string{h}
	for {
		idx := strings.IndexByte(h, '.')
		if idx < 0 || idx == len(h)-1 {
			return suffixes
		}
		h = h[idx+1:]
		suffixes = append(suffixes, h)
	}
}

func serveCSS(req *http.Request) *http.Response {
	cosmeticMu.RLock()
	payload := cosmeticCSS
	cosmeticMu.RUnlock()

	css := buildCosmeticCss(payload, normalizeCosmeticHost(req.URL.Query().Get("h")))
	resp := buildTextResponse(req, 200, "text/css; charset=utf-8", css)
	// The stylesheet depends on the hostname in the query string, so it must
	// not be reused for another site through a shared cache.
	resp.Header.Set("Vary", "X-DITING-Host")
	resp.Header.Set("Cache-Control", "private, max-age=300")
	return resp
}

func serveHealth(req *http.Request) *http.Response {
	cosmeticMu.RLock()
	payload := cosmeticCSS
	cosmeticMu.RUnlock()

	body := fmt.Sprintf(`{"status":"ok","css_bytes":%d}`, len(payload))
	return buildTextResponse(req, 200, "application/json", body)
}

func serve404(req *http.Request) *http.Response {
	return buildTextResponse(req, 404, "text/plain", "Not Found")
}

func buildTextResponse(req *http.Request, status int, contentType, body string) *http.Response {
	return &http.Response{
		StatusCode: status,
		Status:     fmt.Sprintf("%d %s", status, http.StatusText(status)),
		Proto:      "HTTP/1.1",
		ProtoMajor: 1,
		ProtoMinor: 1,
		Header: http.Header{
			"Content-Type":                []string{contentType},
			"Content-Length":              []string{fmt.Sprintf("%d", len(body))},
			"Cache-Control":               []string{"public, max-age=300"},
			"Access-Control-Allow-Origin": []string{"*"},
			"X-DITING":                    []string{"local-asset-server"},
		},
		Body:          readCloserFromString(body),
		ContentLength: int64(len(body)),
		Request:       req,
	}
}

func IsLocalAssetHost(host string) bool {
	h := strings.ToLower(strings.TrimSpace(host))

	if idx := strings.LastIndex(h, ":"); idx != -1 {
		h = h[:idx]
	}
	return h == LocalAssetHost
}

func readCloserFromString(s string) readCloserStr {
	return readCloserStr{strings.NewReader(s)}
}

type readCloserStr struct {
	*strings.Reader
}

func (readCloserStr) Close() error { return nil }

func (cm *CertManager) WarmLocalAssetCert() {
	start := time.Now()
	_, err := cm.getCertForHost(LocalAssetHost)
	if err != nil {
		logf("Local asset server: cert pre-gen failed: %v", err)
	} else {
		logf("Local asset server: cert for %s pre-generated in %v", LocalAssetHost, time.Since(start))
	}
}
