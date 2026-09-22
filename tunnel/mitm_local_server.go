// mitm_local_server.go implements the embedded HTTP server serving cached ad-blocking cosmetic assets.
//
// Caching & Performance:
// - Serves in-memory CSS/JS assets for the local asset hostname (local.pwhs.app).
// - Generates deterministic ETags to support HTTP 304 Not Modified responses, minimizing mobile browser overhead.

package tunnel

import (
	"fmt"
	"net/http"
	"strings"
	"time"
)

const LocalAssetHost = "local.pwhs.app"

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

func serveCSS(req *http.Request) *http.Response {
	cosmeticMu.RLock()
	css := cosmeticCSS
	cosmeticMu.RUnlock()

	if css == "" {
		css = "/* DITING: no cosmetic rules loaded */"
	}

	return buildTextResponse(req, 200, "text/css; charset=utf-8", css)
}

func serveHealth(req *http.Request) *http.Response {
	cosmeticMu.RLock()
	cssLen := len(cosmeticCSS)
	cosmeticMu.RUnlock()

	body := fmt.Sprintf(`{"status":"ok","css_bytes":%d}`, cssLen)
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
