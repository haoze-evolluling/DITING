package core

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"testing"
	"time"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
)

// startMockDoQServer 启动一个最小 DoQ 服务端（RFC 9250）。
//
// 行为：每条 stream 读取一条带 2 字节长度前缀的查询，
// 校验 Message ID 为 0，随后返回同样带长度前缀、ID 归零的应答。
func startMockDoQServer(t *testing.T) (addr string, shutdown func()) {
	t.Helper()

	cert := generateTestTLSCert(t)
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		NextProtos:   []string{doqALPN},
		MinVersion:   tls.VersionTLS13,
	}

	listener, err := quic.ListenAddr("127.0.0.1:0", tlsConfig, &quic.Config{
		Allow0RTT: false,
	})
	if err != nil {
		t.Fatalf("listen mock doq: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	go func() {
		for {
			conn, err := listener.Accept(ctx)
			if err != nil {
				return
			}
			go handleDoQConn(ctx, conn)
		}
	}()

	return listener.Addr().String(), func() {
		cancel()
		_ = listener.Close()
	}
}

func handleDoQConn(ctx context.Context, conn quic.Connection) {
	for {
		stream, err := conn.AcceptStream(ctx)
		if err != nil {
			return
		}
		go handleDoQStream(stream)
	}
}

func handleDoQStream(stream quic.Stream) {
	defer stream.Close()

	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(stream, lenBuf); err != nil {
		return
	}
	qLen := binary.BigEndian.Uint16(lenBuf)
	query := make([]byte, qLen)
	if _, err := io.ReadFull(stream, query); err != nil {
		return
	}

	var qMsg dns.Msg
	if err := qMsg.Unpack(query); err != nil {
		return
	}
	// RFC 9250 §4.2.1：客户端必须以 ID 0 发起查询
	if qMsg.Id != 0 {
		stream.CancelRead(0)
		return
	}

	respMsg := new(dns.Msg)
	respMsg.SetReply(&qMsg)
	respMsg.Id = 0
	rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.1.1.1", qMsg.Question[0].Name))
	respMsg.Answer = append(respMsg.Answer, rr)

	respBytes, err := respMsg.Pack()
	if err != nil {
		return
	}

	_, _ = stream.Write(doqFrame(respBytes))
}

func TestDoQResolver_BasicAndPool(t *testing.T) {
	addr, shutdown := startMockDoQServer(t)
	defer shutdown()

	doq := NewDoQResolver(nil)
	doq.SetTLSConfig(&tls.Config{InsecureSkipVerify: true})
	defer doq.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("doq.example.com")

	// 首次查询建立 QUIC 连接并池化
	resp1, err := doq.Exchange(ctx, rawQuery, addr)
	if err != nil {
		t.Fatalf("first DoQ Exchange failed: %v", err)
	}
	var msg1 dns.Msg
	if err := msg1.Unpack(resp1); err != nil {
		t.Fatalf("unpack DoQ response failed: %v", err)
	}
	if len(msg1.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(msg1.Answer))
	}
	if msg1.Id != 0 {
		t.Fatalf("expected message id 0 per RFC 9250, got %d", msg1.Id)
	}

	// 二次查询复用同一条 QUIC 连接
	resp2, err := doq.Exchange(ctx, rawQuery, addr)
	if err != nil {
		t.Fatalf("second DoQ Exchange (pooled) failed: %v", err)
	}
	var msg2 dns.Msg
	if err := msg2.Unpack(resp2); err != nil {
		t.Fatalf("unpack pooled response failed: %v", err)
	}
	if len(msg2.Answer) != 1 {
		t.Fatalf("expected 1 answer from pooled conn, got %d", len(msg2.Answer))
	}

	_ = doq.Close()
	if _, err := doq.Exchange(ctx, rawQuery, addr); err == nil {
		t.Fatalf("expected error after doq.Close, got nil")
	}
}

func TestDoQResolver_ZeroesMessageID(t *testing.T) {
	addr, shutdown := startMockDoQServer(t)
	defer shutdown()

	doq := NewDoQResolver(nil)
	doq.SetTLSConfig(&tls.Config{InsecureSkipVerify: true})
	defer doq.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 构造非 0 Message ID 的查询，解析器必须在上游前归零
	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn("id-zero.example.com"), dns.TypeA)
	m.Id = 4242
	raw, err := m.Pack()
	if err != nil {
		t.Fatalf("pack query: %v", err)
	}

	normalized, err := doqNormalizeQuery(raw)
	if err != nil {
		t.Fatalf("normalize query: %v", err)
	}
	var normMsg dns.Msg
	if err := normMsg.Unpack(normalized); err != nil {
		t.Fatalf("unpack normalized query: %v", err)
	}
	if normMsg.Id != 0 {
		t.Fatalf("expected normalized id 0, got %d", normMsg.Id)
	}

	// 端到端：服务端对非 0 ID 会拒绝，能拿到应答即证明归零生效
	resp, err := doq.Exchange(ctx, raw, addr)
	if err != nil {
		t.Fatalf("DoQ Exchange with non-zero id failed: %v", err)
	}
	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack response: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(respMsg.Answer))
	}
}

func TestDoQProtocolParsing(t *testing.T) {
	cases := map[string]DNSProtocol{
		"DOQ":   ProtocolDoQ,
		"doq":   ProtocolDoQ,
		"QUIC":  ProtocolDoQ,
		"quic":  ProtocolDoQ,
		"DOH":   ProtocolDoH,
		"DOT":   ProtocolDoT,
		"PLAIN": ProtocolPlain,
	}
	for in, want := range cases {
		if got := ParseProtocol(in); got != want {
			t.Errorf("ParseProtocol(%q) = %q, want %q", in, got, want)
		}
		if !IsValidProtocol(in) {
			t.Errorf("IsValidProtocol(%q) = false, want true", in)
		}
	}

	if ProtocolPlain.IsEncrypted() {
		t.Error("PLAIN must not be encrypted")
	}
	for _, p := range []DNSProtocol{ProtocolDoH, ProtocolDoT, ProtocolDoQ} {
		if !p.IsEncrypted() {
			t.Errorf("%s must be encrypted", p)
		}
	}
}
