// mitm_passthrough.go handles protected upstream dialing and bidirectional traffic relay for bypassed connections.
//
// Dual-Stack Failover:
// - Directly dials destination endpoints using socket protection.
// - Automatically falls back to IPv4 resolution if an IPv6 connection fails, preventing Android ERR_CONNECTION_REFUSED
//   on networks lacking IPv6 routes.
// - Performs zero-allocation bidirectional streaming between client and server sockets.

package tunnel

import (
	"context"
	"io"
	"net"
	"time"
)

func isTLSClientPort(port int) bool {
	return port == 443 || port == 465 || port == 993 || port == 8443
}

func dialUpstream(flow flowID, hostname string, blocker adBlockChecker, protectFn func(fd int) bool) (net.Conn, error) {
	outbound := flowOutbound(newFlowOutbound(outboundProxyConfig{}, protectFn, nil))
	if engine, ok := blocker.(*Engine); ok && engine.flowOutbound != nil {
		outbound = engine.flowOutbound
	}
	if hostname == "" && blocker != nil {
		hostname = blocker.domainForIP(flow.serverIP)
	}

	dst := net.JoinHostPort(flow.serverIP.String(), intToStr(flow.serverPort))
	isV6 := flow.serverIP.To4() == nil
	dialTimeout := flowDialTimeout
	if isV6 {
		dialTimeout = 2 * time.Second
	}

	ctx, cancel := context.WithTimeout(context.Background(), dialTimeout)
	conn, err := outbound.DialTCP(ctx, dst)
	cancel()
	if err == nil {
		return conn, nil
	}

	if isV6 && hostname != "" && blocker != nil {
		if ip, lerr := blocker.lookupIP(hostname); lerr == nil && ip != nil {
			alt := net.JoinHostPort(ip.String(), intToStr(flow.serverPort))
			v4Ctx, v4Cancel := context.WithTimeout(context.Background(), flowDialTimeout)
			altConn, aerr := outbound.DialTCP(v4Ctx, alt)
			v4Cancel()
			if aerr == nil {
				logf("[TcpStack] v6 dial to %s failed (%v); fell back to v4 %s", dst, err, alt)
				return altConn, nil
			}
		}
	}
	logf("[TcpStack] upstream dial %s failed: %v", dst, err)
	return nil, err
}

func relayDirectFromFlow(clientConn net.Conn, flow flowID, blocker adBlockChecker, protectFn func(fd int) bool) {

	if flow.serverIP.To4() == nil && isTLSClientPort(flow.serverPort) {
		peeked, peekedReader, err := peekFlow(clientConn, peekSize, peekTimeout)
		if err == nil && len(peeked) > 0 {
			sni := ""
			if len(peeked) >= 3 && peeked[0] == 0x16 && peeked[1] == 0x03 {
				sni = parseClientHelloSNI(peeked)
			}
			relayDirectPeeked(clientConn, peekedReader, flow, sni, blocker, protectFn)
			return
		}
	}

	remote, err := dialUpstream(flow, "", blocker, protectFn)
	if err != nil {
		return
	}
	defer remote.Close()

	bidiCopyFlow(clientConn, remote)
}

func relayDirectPeeked(clientConn net.Conn, clientReader io.Reader, flow flowID, hostname string, blocker adBlockChecker, protectFn func(fd int) bool) {
	remote, err := dialUpstream(flow, hostname, blocker, protectFn)
	if err != nil {
		return
	}
	defer remote.Close()

	done := make(chan struct{}, 2)
	go func() {
		io.Copy(remote, clientReader)
		if cw, ok := remote.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		io.Copy(clientConn, remote)
		if cw, ok := clientConn.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	<-done
	<-done
}
