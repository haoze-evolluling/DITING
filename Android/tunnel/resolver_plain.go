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

	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			conn.Close()
		case <-done:
		}
	}()

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(queryTimeoutPlain)) {
		deadline = time.Now().Add(queryTimeoutPlain)
	}

	buf := make([]byte, 4096)

	const initialUdpTimeout = 1500 * time.Millisecond
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
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		if time.Now().Before(deadline) {
			_ = conn.SetDeadline(deadline)
			if _, werr := conn.Write(rawQuery); werr == nil {
				n, err = conn.Read(buf)
			}
		}
	}

	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("plain read: %w", err)
	}

	return buf[:n], nil
}

func queryPlainTCPContext(ctx context.Context, outbound flowOutbound, rawQuery []byte, server string) ([]byte, error) {
	dialCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()

	conn, err := outbound.DialTCP(dialCtx, server)
	if err != nil {
		return nil, fmt.Errorf("plain TCP dial: %w", err)
	}
	defer conn.Close()

	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			conn.Close()
		case <-done:
		}
	}()

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
