package tunnel

import (
	"context"
	"io"
	"net"
)

// mitm_passthrough.go — upstream dial (with IPv6→IPv4 fallback) and
// bidirectional relay used when the MITM handler decides NOT to
// intercept a flow: private IPs, non-HTTP ports, non-allowed UIDs, or
// sensitive/pinned domains.

// dialUpstream dials the flow's destination with socket protection,
// falling back to an IPv4 resolution of hostname when the direct-IP
// dial fails: Chrome resolves dual-stack hosts to IPv6, but the Go
// process's underlying network often has no v6 route, so without the
// fallback the client sees ERR_CONNECTION_REFUSED. hostname may be ""
// (gates that trigger before SNI is known); only the direct dial is
// attempted then.
func dialUpstream(flow flowID, hostname string, blocker adBlockChecker, protectFn func(fd int) bool) (net.Conn, error) {
	outbound := flowOutbound(newFlowOutbound(outboundProxyConfig{}, protectFn, nil))
	if engine, ok := blocker.(*Engine); ok && engine.flowOutbound != nil {
		outbound = engine.flowOutbound
	}
	dst := net.JoinHostPort(flow.serverIP.String(), intToStr(flow.serverPort))
	ctx, cancel := context.WithTimeout(context.Background(), flowDialTimeout)
	defer cancel()
	conn, err := outbound.DialTCP(ctx, dst)
	if err == nil {
		return conn, nil
	}

	if hostname != "" && blocker != nil && flow.serverIP.To4() == nil {
		if ip, lerr := blocker.lookupIP(hostname); lerr == nil && ip != nil {
			alt := net.JoinHostPort(ip.String(), intToStr(flow.serverPort))
			if altConn, aerr := outbound.DialTCP(ctx, alt); aerr == nil {
				logf("[TcpStack] v6 dial to %s failed (%v); fell back to v4 %s", dst, err, alt)
				return altConn, nil
			}
		}
	}
	logf("[TcpStack] upstream dial %s failed: %v", dst, err)
	return nil, err
}

// relayDirectFromFlow dials the flow's real destination and pipes bytes
// bidirectionally (no peek replay — used by gates that trigger before
// any read). No absolute SetDeadline: gVisor-side TCP keepalive (60s
// idle, 30s interval, 9 probes) kills genuinely stuck connections, while
// long-lived flows live as long as apps need — a former 3-minute hard
// deadline killed YouTube playback mid-stream as ERR_CONNECTION_ABORTED.
func relayDirectFromFlow(clientConn net.Conn, flow flowID, blocker adBlockChecker, protectFn func(fd int) bool) {
	remote, err := dialUpstream(flow, "", blocker, protectFn)
	if err != nil {
		return
	}
	defer remote.Close()

	bidiCopyFlow(clientConn, remote)
}

// relayDirectPeeked dials the destination and writes the peeked bytes
// to it first, then pipes bidirectionally. Used after peek+classify
// when the classifier decides not to MITM. hostname is the SNI / Host
// (may be "") and enables IPv6→IPv4 fallback when the direct-IP dial
// fails.
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
