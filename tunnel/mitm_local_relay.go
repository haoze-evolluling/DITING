package tunnel

import (
	"bufio"
	"crypto/tls"
	"io"
	"net"
	"net/http"
	"strings"
)

// mitm_local_relay.go — responders for flows whose SNI / Host matches
// the local asset host (local.pwhs.app) or a CNAME rewrite target,
// served entirely from memory without any upstream dial.

// serveLocalAssetTLS completes a TLS handshake (dynamic cert) for a
// connection whose SNI matches the local asset host, then serves
// in-memory assets without any upstream dial.
func serveLocalAssetTLS(conn net.Conn, clientReader io.Reader, certMgr *CertManager, hostname string) {
	tlsCfg := certMgr.GetDynamicTLSConfigForHost(hostname)
	clientTLS := tls.Server(&peekReplayConn{Conn: conn, r: clientReader}, tlsCfg)
	if err := clientTLS.Handshake(); err != nil {
		return
	}
	defer clientTLS.Close()

	rb := bufio.NewReader(clientTLS)
	for {
		req, err := http.ReadRequest(rb)
		if err != nil {
			return
		}
		resp := ServeLocalAsset(req)
		if err := resp.Write(clientTLS); err != nil {
			return
		}
		if req.Close {
			return
		}
	}
}

// serveLocalAssetPlaintext answers an HTTP (no TLS) request targeting
// the local asset host. Kept for symmetry; normally the local asset
// host is only accessed via HTTPS links.
func serveLocalAssetPlaintext(conn net.Conn, clientReader io.Reader) {
	rb := bufio.NewReader(clientReader)
	for {
		req, err := http.ReadRequest(rb)
		if err != nil {
			return
		}
		resp := ServeLocalAsset(req)
		if err := resp.Write(conn); err != nil {
			return
		}
		if req.Close {
			return
		}
	}
}

// CNAME rewrite redirect helpers.

func serveRewriteRedirectTLS(conn net.Conn, clientReader io.Reader, certMgr *CertManager, hostname, target string, engine *Engine, flow flowID) {
	tlsCfg := certMgr.GetDynamicTLSConfigForHost(hostname)
	clientTLS := tls.Server(&peekReplayConn{Conn: conn, r: clientReader}, tlsCfg)
	if err := clientTLS.Handshake(); err != nil {
		engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", "client_tls")
		return
	}
	defer clientTLS.Close()
	serveRewriteRedirect(clientTLS, target, "HTTPS", engine, flow)
}

func serveRewriteRedirectHTTP(conn net.Conn, clientReader io.Reader, target string, engine *Engine, flow flowID) {
	serveRewriteRedirect(&peekReplayConn{Conn: conn, r: clientReader}, target, "HTTP/1.1", engine, flow)
}

func serveRewriteRedirect(conn net.Conn, target, protocol string, engine *Engine, flow flowID) {
	reader := bufio.NewReader(conn)
	for {
		req, err := http.ReadRequest(reader)
		if err != nil {
			return
		}
		location := "https://" + target
		if uri := req.URL.RequestURI(); uri != "" && uri != "/" {
			location += uri
		}
		resp := &http.Response{
			StatusCode: http.StatusFound,
			ProtoMajor: 1,
			ProtoMinor: 1,
			Header:     make(http.Header),
			Body:       io.NopCloser(strings.NewReader("")),
			Request:    req,
		}
		resp.Header.Set("Location", location)
		resp.Header.Set("Content-Length", "0")
		resp.Header.Set("Cache-Control", "no-store")
		if err := resp.Write(conn); err != nil {
			return
		}
		engine.logHTTPEvent(flow, req.Host, protocol, "rewritten", target)
		if req.Close {
			return
		}
	}
}
