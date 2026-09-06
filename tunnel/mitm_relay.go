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

// mitmTLSFlow performs TLS handshake with the client first using our
// dynamic cert. If the client enforces Certificate Pinning, it rejects our
// cert locally in ~1-3ms, avoiding wasteful upstream network dials and radio wakeups.
// Once client TLS succeeds, it dials the real server with TLS validation
// and relays HTTP request/response pairs.
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
	// 1. Handshake with the client first using our dynamic CA-signed cert.
	// If the client is pinning the real cert, it will reject ours immediately.
	tlsCfg := certMgr.GetDynamicTLSConfigForHost(hostname)
	clientTLS := tls.Server(&peekReplayConn{Conn: clientConn, r: clientReader}, tlsCfg)
	if err := clientTLS.Handshake(); err != nil {
		if filter != nil {
			filter.RecordFailure(hostname, err)
		}
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", "client_tls")
		}
		return
	}
	defer clientTLS.Close()

	// 2. Client accepted our certificate! Dial the real server with socket protection
	// and IPv6->IPv4 fallback.
	rawServer, err := dialUpstream(flow, hostname, blocker, protectFn)
	if err != nil {
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", "upstream_tls")
		}
		return
	}

	// Verify the upstream cert against the shared trust store (system roots + bundled ISRG X1/X2).
	clientCertRequested := false
	serverConn := tls.Client(rawServer, upstreamTLSConfig(hostname, &clientCertRequested))
	if err := serverConn.Handshake(); err != nil {
		rawServer.Close()
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", "upstream_tls")
		}
		return
	}
	defer serverConn.Close()

	// 3. Proactive skip check: if the server requested a client certificate (mTLS)
	// or presents an Extended-Validation (EV) certificate, record in auto-blacklist
	// so future flows go direct at Gate 5 without interception.
	if state := serverConn.ConnectionState(); len(state.PeerCertificates) > 0 {
		leaf := state.PeerCertificates[0]
		if clientCertRequested || isExtendedValidation(leaf) {
			reason := "EV certificate"
			if clientCertRequested {
				reason = "client-certificate (mTLS) request"
			}
			logf("MITM: not filtering '%s' — %s; recorded for future passthrough", hostname, reason)
			if filter != nil {
				filter.BlacklistDomainWithReason(hostname, reason)
			}
			if engine != nil {
				engine.logHTTPEvent(flow, hostname, "HTTPS", "decryption_failed", reason)
			}
			return
		}
	}

	// 4. Client and upstream TLS both ready — start HTTP relay and injection loop.
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
