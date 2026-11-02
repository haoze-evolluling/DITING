// resolver_plain.go implements standard UDP and TCP DNS resolution (port 53).
//
// Mobile Network Optimization:
// - Performs initial UDP queries with bounded timeouts (1.5s) to mitigate mobile packet loss,
//   retrying if time permits before falling back to TCP.

package tunnel

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"time"
)

type plainRetryDelayKey struct{}

// withPlainUDPRetryDelay attaches an adaptive initial UDP retry delay to ctx.
func withPlainUDPRetryDelay(ctx context.Context, d time.Duration) context.Context {
	if d <= 0 {
		return ctx
	}
	return context.WithValue(ctx, plainRetryDelayKey{}, d)
}

func plainUDPRetryDelayFromContext(ctx context.Context) time.Duration {
	if d, ok := ctx.Value(plainRetryDelayKey{}).(time.Duration); ok && d > 0 {
		return d
	}
	return 1500 * time.Millisecond
}

func (r *Resolver) queryPlain(rawQuery []byte, server string) ([]byte, error) {
	return r.queryPlainContext(context.Background(), rawQuery, server)
}

func (r *Resolver) queryPlainContext(ctx context.Context, rawQuery []byte, server string) ([]byte, error) {
	host := server
	port := "53"
	if h, p, err := net.SplitHostPort(server); err == nil {
		host = h
		port = p
	}

	r.mu.RLock()
	outbound := r.outbound
	bootstrap := r.bootstrap
	r.mu.RUnlock()

	dialCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()

	targetHost := host
	if bootstrap != nil && bootstrap.IsEnabled() {
		if resolvedIP, rErr := bootstrap.ResolveHost(dialCtx, host); rErr == nil && resolvedIP != "" {
			targetHost = resolvedIP
		}
	}
	targetServer := net.JoinHostPort(targetHost, port)

	if !outbound.SupportsUDP() {
		return queryPlainTCPContext(ctx, outbound, rawQuery, targetServer)
	}
	conn, err := outbound.DialUDP(dialCtx, targetServer)
	if err != nil {
		return nil, fmt.Errorf("plain dial: %w", err)
	}
	defer conn.Close()

	// Close the socket when ctx is cancelled (e.g. another provider won the race)
	// without parking a watcher goroutine per query.
	stopWatch := context.AfterFunc(ctx, func() { conn.Close() })
	defer stopWatch()

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(queryTimeoutPlain)) {
		deadline = time.Now().Add(queryTimeoutPlain)
	}

	buf := make([]byte, 4096)

	initialUdpTimeout := plainUDPRetryDelayFromContext(ctx)
	firstDeadline := time.Now().Add(initialUdpTimeout)
	if firstDeadline.After(deadline) {
		firstDeadline = deadline
	}
	_ = conn.SetDeadline(firstDeadline)

	if _, err := conn.Write(rawQuery); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("plain write: %w", err)
	}

	n, err := conn.Read(buf)
	for retry := 0; err != nil && retry < 2; retry++ {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		now := time.Now()
		if !now.Before(deadline) {
			break
		}
		nextDeadline := deadline
		if retry == 0 {
			if step := now.Add(initialUdpTimeout * 2); step.Before(deadline) {
				nextDeadline = step
			}
		}
		_ = conn.SetDeadline(nextDeadline)
		if _, werr := conn.Write(rawQuery); werr == nil {
			n, err = conn.Read(buf)
		}
	}

	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("plain read: %w", err)
	}

	response := buf[:n]

	// RFC 1035 §4.2.1: a UDP answer with TC=1 is a *truncated* answer, the
	// resolver must retry over TCP. Without this the truncated message was
	// returned as final, cached, and replayed to every subsequent client —
	// which needs the upstream to omit the EDNS0 OPT record in its reply, so
	// the client sees a header-only answer with no address records.
	if isTruncatedResponse(response) {
		tcpResp, tcpErr := queryPlainTCPContext(ctx, outbound, rawQuery, targetServer)
		if tcpErr == nil {
			return tcpResp, nil
		}
		// Keep the truncated UDP answer only when TCP also failed; reporting a
		// hard error here would turn a partially usable answer into SERVFAIL.
		return response, nil
	}

	return response, nil
}

// isTruncatedResponse reports whether a raw DNS message has the TC flag set.
// The header is 12 bytes with the flags at offset 2; TC is bit 1 of the high
// flags byte (0x02).
func isTruncatedResponse(raw []byte) bool {
	return len(raw) >= 12 && raw[2]&0x02 != 0
}

func queryPlainTCPContext(ctx context.Context, outbound flowOutbound, rawQuery []byte, server string) ([]byte, error) {
	dialCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()

	conn, err := outbound.DialTCP(dialCtx, server)
	if err != nil {
		return nil, fmt.Errorf("plain TCP dial: %w", err)
	}
	defer conn.Close()

	// Close the socket when ctx is cancelled (e.g. another provider won the race)
	// without parking a watcher goroutine per query.
	stopWatch := context.AfterFunc(ctx, func() { conn.Close() })
	defer stopWatch()

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(queryTimeoutPlain)) {
		deadline = time.Now().Add(queryTimeoutPlain)
	}
	_ = conn.SetDeadline(deadline)

	length := make([]byte, 2)
	binary.BigEndian.PutUint16(length, uint16(len(rawQuery)))
	if _, err := conn.Write(append(length, rawQuery...)); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("plain TCP write: %w", err)
	}
	if _, err := io.ReadFull(conn, length); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("plain TCP read length: %w", err)
	}
	response := make([]byte, int(binary.BigEndian.Uint16(length)))
	if _, err := io.ReadFull(conn, response); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("plain TCP read: %w", err)
	}
	return response, nil
}
