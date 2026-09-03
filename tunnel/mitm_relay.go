package tunnel

import (
	"bufio"
	"crypto/tls"
	"net"
	"net/http"
	"strings"
)

// mitm_relay.go — MITM TLS/HTTP interception: TLS handshake with the
// client using a dynamic cert, upstream TLS verification, EV/mTLS
// detection with auto-blacklisting on pinning failures, and the HTTP
// request/response relay loop with injection.

// mitmTLSFlow performs the TLS handshake with the client using our
// dynamic cert, dials the real server with TLS validation, and relays
// HTTP request/response pairs — injecting cosmetic CSS into HTML bodies
// via the shared helpers from mitm_proxy.go.
func mitmTLSFlow(
	clientConn net.Conn,
	clientReader interface{ Read([]byte) (int, error) },
	certMgr *CertManager,
	filter *MitmFilter,
	blocker adBlockChecker,
	engine *Engine,
	hostname string,
	flow flowID,
	protectFn func(fd int) bool,
) {
	// Dial the real server first so cert pinning checks catch obvious
	// problems before we commit to MITM. Uses the v6→v4 fallback so
	// dual-stack hosts still connect when the Go process has no v6
	// route on the underlying network.
	rawServer, err := dialUpstream(flow, hostname, blocker, protectFn)
	if err != nil {
		return
	}
	// Verify the upstream cert against the shared trust store (system
	// roots + bundled ISRG X1/X2). Without the bundled roots, Let's
	// Encrypt-backed sites fail verification on devices with a stale
	// system store, silently disabling filtering for a big slice of the
	// web. Record whether the server asks us for a client cert (mTLS).
	clientCertRequested := false
	serverConn := tls.Client(rawServer, upstreamTLSConfig(hostname, &clientCertRequested))
	if err := serverConn.Handshake(); err != nil {
		rawServer.Close()
		// Upstream cert failure → fall back to raw passthrough with
		// replay so the client's own TLS validation can surface a
		// meaningful error (or succeed).
		engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", "upstream_tls")
		relayDirectPeeked(clientConn, clientReader, flow, hostname, blocker, protectFn)
		return
	}
	defer serverConn.Close()

	// Proactive skip (mirrors AdGuard): don't MITM high-assurance sites
	// on the first visit. If the server requested a client certificate
	// (mutual TLS) or presents an Extended-Validation certificate, our
	// forged leaf would break the connection — passthrough instead, and
	// remember the decision so future flows go direct without a probe.
	if state := serverConn.ConnectionState(); len(state.PeerCertificates) > 0 {
		leaf := state.PeerCertificates[0]
		if clientCertRequested || isExtendedValidation(leaf) {
			reason := "EV certificate"
			if clientCertRequested {
				reason = "client-certificate (mTLS) request"
			}
			logf("MITM: not filtering '%s' — %s; passthrough", hostname, reason)
			filter.BlacklistDomain(hostname)
			engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", reason)
			serverConn.Close()
			relayDirectPeeked(clientConn, clientReader, flow, hostname, blocker, protectFn)
			return
		}
	}

	// Handshake with the client using our CA-signed cert. If the
	// client is pinning the real cert it will reject ours; auto-
	// blacklist so future flows to this host go direct.
	tlsCfg := certMgr.GetDynamicTLSConfigForHost(hostname)
	clientTLS := tls.Server(&peekReplayConn{Conn: clientConn, r: clientReader}, tlsCfg)
	if err := clientTLS.Handshake(); err != nil {
		errStr := err.Error()
		if strings.Contains(errStr, "unknown certificate") ||
			strings.Contains(errStr, "handshake failure") ||
			strings.Contains(errStr, "certificate unknown") ||
			strings.Contains(errStr, "bad certificate") ||
			strings.Contains(errStr, "tls:") {
			filter.BlacklistDomain(hostname)
		}
		engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", "client_tls")
		return
	}
	defer clientTLS.Close()

	relayHTTPFlow(clientTLS, serverConn, hostname, blocker, engine, flow, "HTTPS")
}

// mitmHTTPFlow handles plaintext HTTP (port 80) flows. Same gates
// and injection as mitmTLSFlow but no TLS.
func mitmHTTPFlow(
	clientConn net.Conn,
	clientReader interface{ Read([]byte) (int, error) },
	blocker adBlockChecker,
	engine *Engine,
	hostname string,
	flow flowID,
	protectFn func(fd int) bool,
) {
	serverConn, err := dialUpstream(flow, hostname, blocker, protectFn)
	if err != nil {
		return
	}
	defer serverConn.Close()

	relayHTTPFlow(&peekReplayConn{Conn: clientConn, r: clientReader}, serverConn, hostname, blocker, engine, flow, "HTTP/1.1")
}

// relayHTTPFlow relays HTTP request/response pairs on an established
// flow: reads requests from the client, forwards them to the server,
// decompresses and injects into HTML responses, and supports
// local.pwhs.app sub-requests inside the same session.
func relayHTTPFlow(clientConn, serverConn net.Conn, hostname string, blocker adBlockChecker, engine *Engine, flow flowID, protocol string) {
	cr := bufio.NewReader(clientConn)
	sr := bufio.NewReader(serverConn)

	for {
		req, err := http.ReadRequest(cr)
		if err != nil {
			return
		}
		if req.Host == "" {
			req.Host = hostname
		}

		reqHost := req.Host
		if i := strings.IndexByte(reqHost, ':'); i >= 0 {
			reqHost = reqHost[:i]
		}

		// Sub-request local asset inline.
		if IsLocalAssetHost(reqHost) {
			resp := ServeLocalAsset(req)
			resp.Write(clientConn)
			continue
		}


		if engine != nil {
			scheme := "http"
			if protocol == "HTTPS" { scheme = "https" }
			appName := engine.appNameForFlow(flow, ProtocolTCP)
			if blocked, matched := engine.requestFilterDecision(scheme, reqHost, req.URL.EscapedPath(), appName); blocked {
				engine.logHTTPEvent(flow, reqHost, protocol, "blocked", matched)
				writeBlockedHTTPResponse(clientConn, req)
				continue
			}
		}

		if requestAcceptsHTML(req) {
			req.Header.Del("Accept-Encoding")
		}

		if err := req.Write(serverConn); err != nil {
			return
		}
		engine.logHTTPEvent(flow, reqHost, protocol, "allowed", "")

		resp, err := http.ReadResponse(sr, req)
		if err != nil {
			return
		}
		if ShouldInjectHTML(resp.Header.Get("Content-Type")) {
			wrapResponseForInjection(resp)
		}
		if err := resp.Write(clientConn); err != nil {
			resp.Body.Close()
			return
		}
		resp.Body.Close()

		if resp.Close || req.Close {
			return
		}
	}
}
