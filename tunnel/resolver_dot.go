package tunnel

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"time"
)

const (
	dotMaxIdleConnsPerHost = 4
	dotIdleTimeout         = 15 * time.Second
)

var dotSessionCache = tls.NewLRUClientSessionCache(64)

type dotConnEntry struct {
	conn     net.Conn
	tlsConn  *tls.Conn
	lastUsed time.Time
}

func (e *dotConnEntry) close() {
	if e.tlsConn != nil {
		_ = e.tlsConn.Close()
	}
	if e.conn != nil {
		_ = e.conn.Close()
	}
}

func (e *dotConnEntry) isAlive() bool {
	if e.conn == nil || e.tlsConn == nil {
		return false
	}
	_ = e.conn.SetReadDeadline(time.Now())
	var b [1]byte
	n, err := e.conn.Read(b[:])
	_ = e.conn.SetReadDeadline(time.Time{})
	if err == nil && n > 0 {
		return false
	}
	if err != nil {
		var netErr net.Error
		if errors.As(err, &netErr) && netErr.Timeout() {
			return true
		}
		return false
	}
	return true
}

// closeDoTConns closes all idle DoT connections held by this resolver.
func (r *Resolver) closeDoTConns() {
	r.dotMu.Lock()
	defer r.dotMu.Unlock()
	for _, conns := range r.dotConns {
		for _, c := range conns {
			c.close()
		}
	}
	r.dotConns = make(map[string][]*dotConnEntry)
}

func (r *Resolver) popIdleDoTConn(targetServer string) *dotConnEntry {
	r.dotMu.Lock()
	defer r.dotMu.Unlock()

	conns := r.dotConns[targetServer]
	for len(conns) > 0 {
		lastIdx := len(conns) - 1
		c := conns[lastIdx]
		conns = conns[:lastIdx]
		r.dotConns[targetServer] = conns

		if time.Since(c.lastUsed) <= dotIdleTimeout && c.isAlive() {
			return c
		}
		c.close()
	}
	return nil
}

func (r *Resolver) putIdleDoTConn(targetServer string, c *dotConnEntry) {
	r.dotMu.Lock()
	defer r.dotMu.Unlock()

	conns := r.dotConns[targetServer]
	if len(conns) < dotMaxIdleConnsPerHost {
		c.lastUsed = time.Now()
		r.dotConns[targetServer] = append(conns, c)
	} else {
		c.close()
	}
}

func (r *Resolver) dialFreshDoTConn(ctx context.Context, host, targetServer string) (*dotConnEntry, error) {
	r.mu.RLock()
	outbound := r.outbound
	r.mu.RUnlock()

	dialCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()

	conn, err := outbound.DialTCP(dialCtx, targetServer)
	if err != nil {
		return nil, fmt.Errorf("DoT dial: %w", err)
	}

	tlsConn := tls.Client(conn, &tls.Config{
		ServerName:         host,
		MinVersion:         tls.VersionTLS12,
		ClientSessionCache: dotSessionCache,
	})

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(queryTimeoutDoT)) {
		deadline = time.Now().Add(queryTimeoutDoT)
	}
	_ = tlsConn.SetDeadline(deadline)

	if err := tlsConn.HandshakeContext(ctx); err != nil {
		_ = tlsConn.Close()
		_ = conn.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoT TLS handshake: %w", err)
	}

	return &dotConnEntry{
		conn:     conn,
		tlsConn:  tlsConn,
		lastUsed: time.Now(),
	}, nil
}

// queryDoT sends a DNS query via DNS-over-TLS (RFC 7858).
func (r *Resolver) queryDoT(rawQuery []byte, server string) ([]byte, error) {
	return r.queryDoTContext(context.Background(), rawQuery, server)
}

func (r *Resolver) queryDoTContext(ctx context.Context, rawQuery []byte, server string) ([]byte, error) {
	host := server
	port := "853"
	if h, p, err := net.SplitHostPort(server); err == nil {
		host = h
		port = p
	}

	r.mu.RLock()
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

	// Try using an idle pooled connection first with a bounded probe timeout.
	entry := r.popIdleDoTConn(targetServer)
	var resp []byte
	var err error

	if entry != nil {
		probeCtx, probeCancel := context.WithTimeout(ctx, 2*time.Second)
		resp, err = r.executeDoTQuery(probeCtx, entry, rawQuery)
		probeCancel()

		if err != nil {
			// Stale connection failed; close it and prepare to dial fresh
			entry.close()
			entry = nil
		}
	}

	if entry == nil && ctx.Err() == nil {
		entry, err = r.dialFreshDoTConn(ctx, host, targetServer)
		if err != nil {
			return nil, err
		}
		resp, err = r.executeDoTQuery(ctx, entry, rawQuery)
	}

	if err != nil {
		if entry != nil {
			entry.close()
		}
		return nil, err
	}

	// Healthy connection: return to pool.
	r.putIdleDoTConn(targetServer, entry)
	return resp, nil
}

func (r *Resolver) executeDoTQuery(ctx context.Context, entry *dotConnEntry, rawQuery []byte) ([]byte, error) {
	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(queryTimeoutDoT)) {
		deadline = time.Now().Add(queryTimeoutDoT)
	}
	_ = entry.tlsConn.SetDeadline(deadline)

	// DNS over TCP: 2-byte length prefix
	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(rawQuery)))
	if _, err := entry.tlsConn.Write(append(lenBuf, rawQuery...)); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoT write: %w", err)
	}

	if _, err := io.ReadFull(entry.tlsConn, lenBuf); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoT read length: %w", err)
	}
	respLen := binary.BigEndian.Uint16(lenBuf)
	if respLen == 0 || respLen > 4096 {
		return nil, fmt.Errorf("DoT invalid response length: %d", respLen)
	}

	respBuf := make([]byte, respLen)
	if _, err := io.ReadFull(entry.tlsConn, respBuf); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoT read response: %w", err)
	}

	return respBuf, nil
}
