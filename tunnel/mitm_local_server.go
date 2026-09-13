package tunnel

import (
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Local asset server for the fake domain "local.pwhs.app". Instead of
// injecting raw CSS inline (~50-100KB per page, delaying rendering),
// the injector adds a small <link rel="stylesheet"> tag pointing here;
// the MITM proxy recognizes the hostname and serves the asset from
// memory — no upstream dial, no network round-trip, and the browser
// can cache the CSS (304 Not Modified via ETag).

// LocalAssetHost is the fake hostname the proxy intercepts to serve assets.
const LocalAssetHost = "local.pwhs.app"

// ServeLocalAsset handles HTTP requests to local.pwhs.app and returns
// the response to write back to the client: the in-memory asset for
// known paths, or a 404 response for unknown paths.
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

// serveCSS returns the cosmetic filter CSS from memory.
func serveCSS(req *http.Request) *http.Response {
	cosmeticMu.RLock()
	css := cosmeticCSS
	cosmeticMu.RUnlock()

	if css == "" {
		css = "/* BlockAds: no cosmetic rules loaded */"
	}

	return buildTextResponse(req, 200, "text/css; charset=utf-8", css)
}

// serveHealth returns a simple health check (useful for debugging).
func serveHealth(req *http.Request) *http.Response {
	cosmeticMu.RLock()
	cssLen := len(cosmeticCSS)
	cosmeticMu.RUnlock()

	body := fmt.Sprintf(`{"status":"ok","css_bytes":%d}`, cssLen)
	return buildTextResponse(req, 200, "application/json", body)
}

// serve404 returns a 404 for unknown paths.
func serve404(req *http.Request) *http.Response {
	return buildTextResponse(req, 404, "text/plain", "Not Found")
}

// buildTextResponse creates an *http.Response with the given status, content-type, and body.
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
			"Cache-Control":              []string{"public, max-age=300"}, // 5min cache
			"Access-Control-Allow-Origin": []string{"*"},
			"X-BlockAds":                 []string{"local-asset-server"},
		},
		Body:          readCloserFromString(body),
		ContentLength: int64(len(body)),
		Request:       req,
	}
}

// IsLocalAssetHost returns true if the given hostname matches the local asset server.
func IsLocalAssetHost(host string) bool {
	h := strings.ToLower(strings.TrimSpace(host))
	// Strip port if present
	if idx := strings.LastIndex(h, ":"); idx != -1 {
		h = h[:idx]
	}
	return h == LocalAssetHost
}

// readCloserFromString wraps a string in an io.ReadCloser.
func readCloserFromString(s string) readCloserStr {
	return readCloserStr{strings.NewReader(s)}
}

type readCloserStr struct {
	*strings.Reader
}

func (readCloserStr) Close() error { return nil }

// WarmLocalAssetCert pre-generates the TLS certificate for local.pwhs.app
// so the first request doesn't incur cert generation latency.
func (cm *CertManager) WarmLocalAssetCert() {
	start := time.Now()
	_, err := cm.getCertForHost(LocalAssetHost)
	if err != nil {
		logf("Local asset server: cert pre-gen failed: %v", err)
	} else {
		logf("Local asset server: cert for %s pre-generated in %v", LocalAssetHost, time.Since(start))
	}
}
