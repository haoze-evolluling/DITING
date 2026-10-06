package core

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"time"

	"github.com/miekg/dns"
)

const (
	defaultPlainConnectTimeout = 3 * time.Second
	defaultPlainQueryTimeout   = 5 * time.Second
	defaultUDPInitialTimeout   = 1500 * time.Millisecond
)

// PlainResolver 实现基于标准 UDP 和 TCP 53 端口的上游解析器
type PlainResolver struct {
	bootstrap *BootstrapResolver
}

// NewPlainResolver 创建普通 DNS 解析器
func NewPlainResolver(bootstrap *BootstrapResolver) *PlainResolver {
	return &PlainResolver{
		bootstrap: bootstrap,
	}
}

// SetBootstrap 更新引导解析器引用
func (p *PlainResolver) SetBootstrap(bootstrap *BootstrapResolver) {
	p.bootstrap = bootstrap
}

// Exchange 在给定的 Context 下向上游服务器发送原始 DNS 请求并等待应答
func (p *PlainResolver) Exchange(ctx context.Context, rawQuery []byte, server string) ([]byte, error) {
	host := server
	port := "53"
	if h, pt, err := net.SplitHostPort(server); err == nil {
		host = h
		port = pt
	}

	dialCtx, cancel := context.WithTimeout(ctx, defaultPlainConnectTimeout)
	defer cancel()

	targetHost := host
	if p.bootstrap != nil && p.bootstrap.IsEnabled() {
		if resolvedIP, rErr := p.bootstrap.ResolveHost(dialCtx, host); rErr == nil && resolvedIP != "" {
			targetHost = resolvedIP
		}
	}
	targetServer := net.JoinHostPort(targetHost, port)

	// 首先尝试 UDP 发送请求
	resp, err := p.queryUDP(ctx, rawQuery, targetServer)
	if err == nil {
		// 检查响应是否截断 (Truncated)
		var msg dns.Msg
		if uErr := msg.Unpack(resp); uErr == nil && msg.Truncated {
			// TC 标志置位，回退至 TCP 重试
			return p.queryTCP(ctx, rawQuery, targetServer)
		}
		return resp, nil
	}

	// UDP 失败或超时，回退至 TCP 重试
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	return p.queryTCP(ctx, rawQuery, targetServer)
}

func (p *PlainResolver) queryUDP(ctx context.Context, rawQuery []byte, targetServer string) ([]byte, error) {
	dialer := &net.Dialer{Timeout: defaultPlainConnectTimeout}
	conn, err := dialer.DialContext(ctx, "udp", targetServer)
	if err != nil {
		return nil, fmt.Errorf("udp dial %s: %w", targetServer, err)
	}
	defer conn.Close()

	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			_ = conn.Close()
		case <-done:
		}
	}()

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(defaultPlainQueryTimeout)) {
		deadline = time.Now().Add(defaultPlainQueryTimeout)
	}

	firstDeadline := time.Now().Add(defaultUDPInitialTimeout)
	if firstDeadline.After(deadline) {
		firstDeadline = deadline
	}
	_ = conn.SetDeadline(firstDeadline)

	if _, err := conn.Write(rawQuery); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("udp write: %w", err)
	}

	buf := make([]byte, 4096)
	n, err := conn.Read(buf)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		// 首次读取超时且仍在整体 Deadline 内，重试一次
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
		return nil, fmt.Errorf("udp read: %w", err)
	}

	return buf[:n], nil
}

func (p *PlainResolver) queryTCP(ctx context.Context, rawQuery []byte, targetServer string) ([]byte, error) {
	dialer := &net.Dialer{Timeout: defaultPlainConnectTimeout}
	conn, err := dialer.DialContext(ctx, "tcp", targetServer)
	if err != nil {
		return nil, fmt.Errorf("tcp dial %s: %w", targetServer, err)
	}
	defer conn.Close()

	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			_ = conn.Close()
		case <-done:
		}
	}()

	deadline, ok := ctx.Deadline()
	if !ok || deadline.After(time.Now().Add(defaultPlainQueryTimeout)) {
		deadline = time.Now().Add(defaultPlainQueryTimeout)
	}
	_ = conn.SetDeadline(deadline)

	length := make([]byte, 2)
	binary.BigEndian.PutUint16(length, uint16(len(rawQuery)))
	if _, err := conn.Write(append(length, rawQuery...)); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("tcp write: %w", err)
	}

	if _, err := io.ReadFull(conn, length); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("tcp read length: %w", err)
	}

	respLen := int(binary.BigEndian.Uint16(length))
	if respLen == 0 || respLen > 65535 {
		return nil, fmt.Errorf("invalid tcp response length: %d", respLen)
	}

	response := make([]byte, respLen)
	if _, err := io.ReadFull(conn, response); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("tcp read body: %w", err)
	}

	return response, nil
}
