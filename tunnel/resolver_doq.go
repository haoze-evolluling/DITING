package tunnel

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strings"
	"time"

	"github.com/quic-go/quic-go"
)

// queryDoQ sends a DNS query via DNS-over-QUIC (RFC 9250).
func (r *Resolver) queryDoQ(rawQuery []byte, doqURL string) ([]byte, error) {
	return r.queryDoQContext(context.Background(), rawQuery, doqURL)
}

func (r *Resolver) queryDoQContext(ctx context.Context, rawQuery []byte, doqURL string) ([]byte, error) {
	host, port := parseDoQURL(doqURL)
	if host == "" {
		return nil, fmt.Errorf("invalid DoQ URL: %s", doqURL)
	}

	dialCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()

	conn, err := r.getOrCreateQUICConnContext(dialCtx, host, port)
	if err != nil {
		return nil, fmt.Errorf("DoQ connection: %w", err)
	}

	streamCtx, cancelStream := context.WithTimeout(ctx, queryTimeoutDoQ)
	defer cancelStream()

	stream, err := conn.OpenStreamSync(streamCtx)
	if err != nil {
		// Connection may be stale, reset and retry
		r.resetQUICConn()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		conn, err = r.getOrCreateQUICConnContext(dialCtx, host, port)
		if err != nil {
			return nil, fmt.Errorf("DoQ reconnect: %w", err)
		}
		stream, err = conn.OpenStreamSync(streamCtx)
		if err != nil {
			return nil, fmt.Errorf("DoQ stream: %w", err)
		}
	}
	defer stream.Close()

	// RFC 9250: 2-byte length prefix + DNS message
	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(rawQuery)))
	if _, err := stream.Write(append(lenBuf, rawQuery...)); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoQ write: %w", err)
	}
	_ = stream.Close()

	respData, err := io.ReadAll(io.LimitReader(stream, 65535))
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoQ read: %w", err)
	}

	// RFC 9250: response may have 2-byte length prefix
	if len(respData) >= 2 {
		respLen := binary.BigEndian.Uint16(respData[:2])
		if int(respLen) == len(respData)-2 {
			return respData[2:], nil
		}
	}

	return respData, nil
}

func (r *Resolver) getOrCreateQUICConn(host, port string) (quic.Connection, error) {
	ctx, cancel := context.WithTimeout(context.Background(), connectTimeout)
	defer cancel()
	return r.getOrCreateQUICConnContext(ctx, host, port)
}

func (r *Resolver) getOrCreateQUICConnContext(ctx context.Context, host, port string) (quic.Connection, error) {
	r.quicMu.Lock()
	defer r.quicMu.Unlock()

	addr := net.JoinHostPort(host, port)
	if r.quicConn != nil && r.quicServer == addr {
		return r.quicConn, nil
	}

	r.mu.RLock()
	outbound := r.outbound
	bootstrap := r.bootstrap
	r.mu.RUnlock()
	if !outbound.SupportsUDP() {
		return nil, errOutboundUDPUnsupported
	}
	udpConn, err := outbound.OpenPacket(ctx)
	if err != nil {
		return nil, fmt.Errorf("DoQ packet outbound: %w", err)
	}

	targetHost := host
	if bootstrap != nil && bootstrap.IsEnabled() {
		if resolvedIP, rErr := bootstrap.ResolveHost(ctx, host); rErr == nil && resolvedIP != "" {
			targetHost = resolvedIP
		}
	}

	var udpAddr net.Addr = unresolvedUDPAddr(net.JoinHostPort(targetHost, port))
	if _, proxied := outbound.(*proxyFlowOutbound); !proxied {
		resolved, resolveErr := net.ResolveUDPAddr("udp", net.JoinHostPort(targetHost, port))
		if resolveErr != nil {
			udpConn.Close()
			return nil, fmt.Errorf("DoQ resolve UDP: %w", resolveErr)
		}
		udpAddr = resolved
	}

	tlsConf := &tls.Config{
		ServerName: host,
		NextProtos: []string{"doq"},
		MinVersion: tls.VersionTLS13,
	}

	transport := &quic.Transport{Conn: udpConn}
	conn, err := transport.Dial(ctx, udpAddr, tlsConf, &quic.Config{
		MaxIdleTimeout: 30 * time.Second,
	})
	if err != nil {
		udpConn.Close()
		return nil, fmt.Errorf("DoQ dial: %w", err)
	}

	r.quicConn = conn
	r.quicServer = addr
	return conn, nil
}

type unresolvedUDPAddr string

func (a unresolvedUDPAddr) Network() string { return "udp" }
func (a unresolvedUDPAddr) String() string  { return string(a) }

// resetQUICConn closes and clears the QUIC connection.
func (r *Resolver) resetQUICConn() {
	r.quicMu.Lock()
	defer r.quicMu.Unlock()

	if r.quicConn != nil {
		r.quicConn.CloseWithError(quic.ApplicationErrorCode(0), "reset")
		r.quicConn = nil
	}
}

// parseDoQURL parses a DoQ URL into hostname and port.
func parseDoQURL(url string) (host, port string) {
	s := url
	for _, prefix := range []string{"quic://", "https://", "doq://"} {
		s = strings.TrimPrefix(s, prefix)
	}

	if idx := strings.IndexByte(s, '/'); idx >= 0 {
		s = s[:idx]
	}

	host, port, err := net.SplitHostPort(s)
	if err != nil {
		return s, "853"
	}
	return host, port
}
