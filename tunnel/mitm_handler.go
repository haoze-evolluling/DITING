// mitm_handler.go handles terminated TCP flows (ports 80 and 443) from the userspace network stack.
//
// Decision Pipeline:
// - Gate 0: Evaluates application DoT policy.
// - Gate 1: Bypasses loopback and private IP subnets.
// - Gate 2: Sniffs initial stream bytes to detect TLS ClientHello vs plaintext HTTP.
// - Gate 3: Consults MitmFilter to route flows either to TLS decryption (mitmTLSFlow) or direct passthrough (dialUpstream).

package tunnel

import (
	"net"
	"strings"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/core/adapter"
)

const (
	peekSize = 4 * 1024

	peekTimeout = 10 * time.Second
)

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
		if eng != nil {
			if eng.isUIDBlocked(uid) {
				eng.logBlockedConnection(flow, ProtocolTCP, "uid_blocked")
				return
			}
			if !eng.appAllowlistConnectionAllowed(uid, flow.serverIP) {
				eng.logBlockedConnection(flow, ProtocolTCP, "app_allowlist_blocked")
				return
			}
		}

		if flow.serverIP.IsUnspecified() {
			return
		}

		if eng != nil {
			eng.logConnection(flow, ProtocolTCP)
		}

		var clientConn net.Conn = conn
		if eng != nil && eng.trafficTracker != nil {
			clientConn = eng.trafficTracker.WrapClientConn(conn, uid)
		}

		if flow.serverPort == 853 {
			if eng != nil {
				eng.logBlockedConnection(flow, ProtocolTCP, "blocked_encrypted_dns")
			}
			return
		}

		if flow.serverPort == 53 && eng != nil {
			handleDNSOverTCP(conn, eng, uid)
			return
		}

		if isLoopbackOrInternal(flow.serverIP.String()) {
			relayDirectFromFlow(clientConn, flow, blocker, protectFn)
			return
		}

		if flow.serverPort != 443 && flow.serverPort != 80 {
			relayDirectFromFlow(clientConn, flow, blocker, protectFn)
			return
		}

		if uid == UIDUnknown || !filter.IsUIDAllowed(uid) {
			relayDirectFromFlow(clientConn, flow, blocker, protectFn)
			return
		}

		peeked, peekedReader, err := peekFlow(clientConn, peekSize, peekTimeout)
		if err != nil || len(peeked) == 0 {
			return
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

			relayDirectPeeked(clientConn, peekedReader, flow, "", blocker, protectFn)
			return
		}

		hostname := sni
		if hostname == "" {

			hostname = flow.serverIP.String()
		}
		hostname = strings.ToLower(strings.TrimSpace(hostname))

		if IsLocalAssetHost(hostname) {
			if classification == classTLS {
				serveLocalAssetTLS(clientConn, peekedReader, certMgr, hostname)
			} else {
				serveLocalAssetPlaintext(clientConn, peekedReader)
			}
			return
		}

		if eng != nil {
			if target := eng.rewriteCNAME(hostname); target != "" {
				if classification == classTLS {
					serveRewriteRedirectTLS(clientConn, peekedReader, certMgr, hostname, target, eng, flow)
				} else {
					serveRewriteRedirectHTTP(clientConn, peekedReader, target, eng, flow)
				}
				return
			}
		}

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

		if !filter.IsInterceptionAllowed(hostname) {
			eng.logHTTPEvent(flow, hostname, protocolName(classification), "passthrough", "passthrough")
			relayDirectPeeked(clientConn, peekedReader, flow, hostname, blocker, protectFn)
			return
		}

		if classification == classTLS {
			mitmTLSFlow(clientConn, peekedReader, certMgr, filter, blocker, eng, hostname, flow, protectFn)
		} else {
			mitmHTTPFlow(clientConn, peekedReader, blocker, eng, hostname, flow, protectFn)
		}
	}
}

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
