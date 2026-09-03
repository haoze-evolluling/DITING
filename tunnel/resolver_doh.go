package tunnel

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// buildDoHClient creates an HTTP client with protected sockets for DoH.
func buildDoHClient(outbound flowOutbound, bootstrap *bootstrapResolver) *http.Client {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			target := address
			if bootstrap != nil && bootstrap.IsEnabled() {
				if host, port, err := net.SplitHostPort(address); err == nil {
					if resolvedIP, rErr := bootstrap.ResolveHost(ctx, host); rErr == nil && resolvedIP != "" {
						target = net.JoinHostPort(resolvedIP, port)
					}
				}
			}
			return outbound.DialTCP(ctx, target)
		},
		ForceAttemptHTTP2:   true,
		MaxIdleConns:        5,
		MaxIdleConnsPerHost: 2,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: connectTimeout,
	}
	return &http.Client{
		Transport: transport,
		Timeout:   queryTimeoutDoH,
	}
}

// queryDoH sends a DNS query via DNS-over-HTTPS (RFC 8484 POST).
func (r *Resolver) queryDoH(rawQuery []byte, dohURL string) ([]byte, error) {
	return r.queryDoHContext(context.Background(), rawQuery, dohURL)
}

func (r *Resolver) queryDoHContext(ctx context.Context, rawQuery []byte, dohURL string) ([]byte, error) {
	if dohURL == "" {
		return nil, fmt.Errorf("DoH URL not configured")
	}

	var resp *http.Response
	var err error

	for attempt := 1; attempt <= 2; attempt++ {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		req, reqErr := http.NewRequestWithContext(ctx, "POST", dohURL, bytes.NewReader(rawQuery))
		if reqErr != nil {
			return nil, fmt.Errorf("DoH request: %w", reqErr)
		}
		req.Header.Set("Content-Type", "application/dns-message")
		req.Header.Set("Accept", "application/dns-message")

		resp, err = r.httpClient.Do(req)
		if err == nil {
			break
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		errStr := err.Error()
		if strings.Contains(errStr, "EOF") && attempt == 1 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(10 * time.Millisecond):
			}
			continue
		}
		return nil, fmt.Errorf("DoH request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 403 {
		return nil, fmt.Errorf("DoH rate limited (403)")
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("DoH status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 65535))
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("DoH read: %w", err)
	}

	return body, nil
}
