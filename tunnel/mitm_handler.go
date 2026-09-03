package tunnel

import (
	"net"
	"strings"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

// mitm_handler.go — flow-mode MITM handler.
//
// Attached for port 443/80 TCP flows when the stack is configured with a
// CertManager + MitmFilter via Engine.StartStackMitm. Decision flow mirrors
// the legacy MitmProxy (mitm_proxy.go handleConnect) but operates on
// terminated TCP flows from the userspace stack rather than HTTP CONNECT
// requests:
//
//   Gate 0: selected app DoT policy
//   Gate 1: loopback / private IP → passthrough
//   Gate 1: port != 443/80        → passthrough
//   Gate 2: UID not in allowlist  → passthrough
//   Gate 3: peek first bytes      → classify TLS / HTTP, extract SNI / Host
//   Gate 4: ad-block blocker      → close
//   Gate 5: interception filter   → passthrough (sensitive / pinned domain)
//   Gate 6: local asset server    → serve from memory
//   Gate 7: MITM                  → TLS handshake with our cert, relay HTTP + inject
//
// Every non-MITM path uses the protected dialer so sockets bypass the VPN
// loop.
//
// Implementation is split across companion files:
//   mitm_sniffer.go      — peek, protocol parsing, peekReplayConn, intToStr
//   mitm_passthrough.go  — dialUpstream, relayDirectFromFlow, relayDirectPeeked
//   mitm_local_relay.go  — local asset / CNAME rewrite responders
//   mitm_relay.go        — mitmTLSFlow, mitmHTTPFlow, relayHTTPFlow

const (
	// peekSize must be large enough to contain a full TLS ClientHello
	// including any SNI extension. 4 KB is the modern ceiling.
	peekSize = 4 * 1024

	// peekTimeout bounds how long we wait for the client's first bytes
	// before closing the flow. Browsers typically send data within a few
	// ms of the TCP SYN-ACK; without this a stuck flow would wedge a
	// handler goroutine.
	peekTimeout = 10 * time.Second
)

// newMitmTcpHandler returns a TCP flow handler that MITMs HTTPS/HTTP
// flows for eligible apps and passes every other flow through directly
// with socket protection. The handler owns the flow for its lifetime.
func newMitmTcpHandler(
	certMgr *CertManager,
	filter *MitmFilter,
	blocker adBlockChecker,
	uidr UIDResolver,
	protectFn func(fd int) bool,
) TcpFlowHandler {
	return func(conn adapter.TCPConn) {
		defer conn.Close()

		flow := tcpFlowID(conn)
		uid := resolveFlowUID(uidr, ProtocolTCP, flow)
		eng, _ := blocker.(*Engine)
		if eng != nil && (eng.isUIDBlocked(uid) || !eng.appAllowlistConnectionAllowed(uid, flow.serverIP)) {
			return
		}

		if flow.serverIP.IsUnspecified() {
			return
		}

		// Connection log (full-tunnel): surface every flow with its owning
		// app + destination, so apps that barely use DNS (Telegram/WhatsApp
		// → hard-coded IPs) are visible in the log screen.
		if eng != nil {
			eng.logConnection(flow, ProtocolTCP)
		}

		var clientConn net.Conn = conn
		if eng != nil && eng.trafficTracker != nil {
			clientConn = eng.trafficTracker.WrapClientConn(conn, uid)
		}

		// Resolve UID first. DoT is blocked only for explicitly selected apps
		// and only when the user enabled the anti-bypass setting.
		if flow.serverPort == 853 && eng != nil && eng.blockEncryptedDNS.Load() &&
			uid != UIDUnknown && filter.IsUIDAllowed(uid) {
			return
		}

		// Gate 0 — never MITM private / loopback destinations. These
		// are local services (LAN printers, router admin pages) that
		// often have self-signed certs or none at all.
		if isLoopbackOrInternal(flow.serverIP.String()) {
			relayDirectFromFlow(clientConn, flow, blocker, protectFn)
			return
		}

		// Gate 1 — only attempt MITM on HTTP/HTTPS well-known ports.
		if flow.serverPort != 443 && flow.serverPort != 80 {
			relayDirectFromFlow(clientConn, flow, blocker, protectFn)
			return
		}

		// Gate 2 — only explicitly allowed UIDs may be intercepted. An empty
		// allowlist and UID lookup failures both fail closed to passthrough.
		if uid == UIDUnknown || !filter.IsUIDAllowed(uid) {
			relayDirectFromFlow(clientConn, flow, blocker, protectFn)
			return
		}

		// Gate 3 — peek first bytes to classify and extract SNI / Host.
		peeked, peekedReader, err := peekFlow(clientConn, peekSize, peekTimeout)
		if err != nil || len(peeked) == 0 {
			return // client closed before sending / timeout
		}

		sni := ""
		var classification flowClass
		if len(peeked) >= 3 && peeked[0] == 0x16 && peeked[1] == 0x03 {
			classification = classTLS
			sni = parseClientHelloSNI(peeked)
		} else if looksLikeHTTPRequest(peeked) {
			classification = classHTTP
			sni = parseHTTPHost(peeked)
		} else {
			// Unknown protocol on 443/80 — probably something proxied
			// through these ports that isn't TLS or HTTP. Passthrough.
			relayDirectPeeked(clientConn, peekedReader, flow, "", blocker, protectFn)
			return
		}

		hostname := sni
		if hostname == "" {
			// Fall back to destination IP when we couldn't parse a host.
			hostname = flow.serverIP.String()
		}
		hostname = strings.ToLower(strings.TrimSpace(hostname))

		// Internal hosts precede all rewrite, allow, and block rules.
		if IsLocalAssetHost(hostname) {
			if classification == classTLS {
				serveLocalAssetTLS(clientConn, peekedReader, certMgr, hostname)
			} else {
				serveLocalAssetPlaintext(clientConn, peekedReader)
			}
			return
		}

		// CNAME domain rewrites are user-requested navigation redirects. They
		// must be served locally before passthrough and upstream TLS checks:
		// the source domain may not exist and therefore has no upstream cert.
		if eng != nil {
			if target := eng.rewriteTarget(hostname); target != "" {
				if classification == classTLS {
					serveRewriteRedirectTLS(clientConn, peekedReader, certMgr, hostname, target, eng, flow)
				} else {
					serveRewriteRedirectHTTP(clientConn, peekedReader, target, eng, flow)
				}
				return
			}
		}

		// A TLS domain rule must be checked before the MITM decision. Domains
		// that reject our certificate cannot reach relayHTTPFlow, where the
		// normal decrypted-request rule check runs; otherwise they are recorded
		// as client_tls failures and then auto-passed through permanently.
		if classification == classTLS && eng != nil {
			appName := eng.appNameForFlow(flow, ProtocolTCP)
			if blocked, reason := eng.checkDomainBlockedAndReason(hostname, appName); blocked {
				if reason == "" {
					reason = "https_domain_rule"
				}
				eng.logHTTPEvent(flow, hostname, "HTTPS", "blocked", reason)
				return
			}
		}

		// Gate 5 — sensitive / cert-pinned domain → passthrough so the
		// client's own TLS validation succeeds.
		if !filter.IsInterceptionAllowed(hostname) {
			eng.logHTTPEvent(flow, hostname, protocolName(classification), "decryption_failed", "passthrough")
			relayDirectPeeked(clientConn, peekedReader, flow, hostname, blocker, protectFn)
			return
		}

		// Gate 7 — MITM.
		if classification == classTLS {
			mitmTLSFlow(clientConn, peekedReader, certMgr, filter, blocker, eng, hostname, flow, protectFn)
		} else {
			mitmHTTPFlow(clientConn, peekedReader, blocker, eng, hostname, flow, protectFn)
		}
	}
}

// newMitmUdpHandler wraps the protected UDP relay with QUIC suppression
// for browser UIDs: browsers prefer HTTP/3 (QUIC over UDP 443), which
// would escape TCP-TLS MITM entirely, so UDP 443 is dropped for allowed
// UIDs to force a fast fallback to TCP TLS. Everything else relays
// normally (DNS is handled before the stack; other apps' QUIC and browser
// QUIC to non-443 ports are untouched). Mirrors AdGuard forcing TCP when
// HTTP/3 filtering is on.
func newMitmUdpHandler(filter *MitmFilter, uidr UIDResolver, protectFn func(fd int) bool) UdpFlowHandler {
	base := newProtectedUdpHandler(uidr, protectFn)
	return func(conn adapter.UDPConn) {
		flow := udpFlowID(conn)
		if flow.serverPort == 443 && filter != nil && filter.HasAllowedUIDs() {
			uid := resolveFlowUID(uidr, ProtocolUDP, flow)
			if uid != UIDUnknown && filter.IsUIDAllowed(uid) {
				_ = conn.Close()
				return
			}
		}
		base(conn)
	}
}

type flowClass int

const (
	classUnknown flowClass = iota
	classTLS
	classHTTP
)

func protocolName(classification flowClass) string {
	if classification == classTLS {
		return "HTTPS"
	}
	return "HTTP/1.1"
}
