package tunnel

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"time"
)

// queryPlain sends a DNS query via UDP when supported and otherwise uses TCP.
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
	// UDP packets can be dropped on mobile networks.
	// Wait up to initialUdpTimeout (1.5s) for first attempt; if no response and time remains, retransmit once.
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
		// If timed out on first attempt and remaining time permits, retransmit query once
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

func queryPlainTCP(ctx context.Context, outbound flowOutbound, rawQuery []byte, server string) ([]byte, error) {
	return queryPlainTCPContext(ctx, outbound, rawQuery, server)
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

// protectedDialer wraps net.Dialer to protect sockets from VPN routing loop.
type protectedDialer struct {
	protectFn func(fd int) bool
}

func (d *protectedDialer) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	dialer := &net.Dialer{Timeout: connectTimeout}
	conn, err := dialer.DialContext(ctx, network, addr)
	if err != nil {
		return nil, err
	}

	if d.protectFn != nil {
		var rawConn interface{ Control(func(fd uintptr)) error }
		switch c := conn.(type) {
		case *net.TCPConn:
			rawConn, _ = c.SyscallConn()
		case *net.UDPConn:
			rawConn, _ = c.SyscallConn()
		}
		if rawConn != nil {
			rawConn.Control(func(fd uintptr) {
				d.protectFn(int(fd))
			})
		}
	}

	return conn, nil
}
