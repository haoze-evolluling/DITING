// mitm_relay.go manages TLS/HTTP MITM interception and request relaying.
//
// Client-First Handshake Optimization:
// - Performs TLS handshake with the client first using dynamic CA-minted certificates. Clients enforcing Certificate
//   Pinning abort the handshake locally in 1-3ms, avoiding wasted upstream radio and cellular battery consumption.
// - Following a successful client handshake, establishes protected upstream TLS connections, verifies server certificates,
//   and executes bidirectional HTTP request/response piping with streaming cosmetic injection.

package tunnel

import (
	"bufio"
	"crypto/tls"
	"net"
	"net/http"
	"strings"
)

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

	tlsCfg := certMgr.GetDynamicTLSConfigForHost(hostname)
	clientTLS := tls.Server(&peekReplayConn{Conn: clientConn, r: clientReader}, tlsCfg)
	if err := clientTLS.Handshake(); err != nil {
		if filter != nil {
			filter.RecordFailure(hostname, err)
		}
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTPS", "handshake_failed", "client_tls")
		}
		return
	}
	defer clientTLS.Close()

	rawServer, err := dialUpstream(flow, hostname, blocker, protectFn)
	if err != nil {
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTPS", "upstream_failed", "upstream_tls")
		}
		return
	}

	clientCertRequested := false
	serverConn := tls.Client(rawServer, upstreamTLSConfig(hostname, &clientCertRequested))
	if err := serverConn.Handshake(); err != nil {
		rawServer.Close()
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTPS", "upstream_failed", "upstream_tls")
		}
		return
	}
	defer serverConn.Close()

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
				engine.logHTTPEvent(flow, hostname, "HTTPS", "handshake_failed", reason)
			}
			return
		}
	}

	relayHTTPFlow(clientTLS, serverConn, hostname, blocker, engine, flow, "HTTPS")
}

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
		if engine != nil {
			engine.logHTTPEvent(flow, hostname, "HTTP/1.1", "upstream_failed", "upstream_dial")
		}
		return
	}
	defer serverConn.Close()

	relayHTTPFlow(&peekReplayConn{Conn: clientConn, r: clientReader}, serverConn, hostname, blocker, engine, flow, "HTTP/1.1")
}

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

		if IsLocalAssetHost(reqHost) {
			resp := ServeLocalAsset(req)
			resp.Write(clientConn)
			continue
		}

		if engine != nil {
			scheme := "http"
			if protocol == "HTTPS" {
				scheme = "https"
			}
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
			if engine != nil {
				engine.logHTTPEvent(flow, reqHost, protocol, "error", "upstream_write_failed")
			}
			return
		}

		resp, err := http.ReadResponse(sr, req)
		if err != nil {
			if engine != nil {
				engine.logHTTPEvent(flow, reqHost, protocol, "error", "upstream_read_failed")
			}
			return
		}
		if ShouldInjectHTML(resp.Header.Get("Content-Type")) {
			wrapResponseForInjection(resp)
		}
		if err := resp.Write(clientConn); err != nil {
			resp.Body.Close()
			if engine != nil {
				engine.logHTTPEvent(flow, reqHost, protocol, "error", "client_write_failed")
			}
			return
		}
		if engine != nil {
			engine.logHTTPEvent(flow, reqHost, protocol, "allowed", "")
		}
		resp.Body.Close()

		if resp.Close || req.Close {
			return
		}
	}
}
