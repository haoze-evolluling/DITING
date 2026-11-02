package core

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"testing"
	"time"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
)

// startMockDoH3Server 启动一个最小 DoH3 服务端（RFC 8484 over HTTP/3）。
//
// 仅接受 POST /dns-query 且 Content-Type 为 application/dns-message 的请求，
// 便于同时验证传输层与内容类型约束。
func startMockDoH3Server(t *testing.T) (baseURL string, shutdown func()) {
	t.Helper()

	cert := generateTestTLSCert(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/dns-query", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/dns-message" {
			http.Error(w, "unsupported media type", http.StatusUnsupportedMediaType)
			return
		}

		body, err := io.ReadAll(io.LimitReader(r.Body, 65535))
		if err != nil {
			http.Error(w, "read body failed", http.StatusBadRequest)
			return
		}

		var qMsg dns.Msg
		if err := qMsg.Unpack(body); err != nil || len(qMsg.Question) == 0 {
			http.Error(w, "malformed query", http.StatusBadRequest)
			return
		}

		respMsg := new(dns.Msg)
		respMsg.SetReply(&qMsg)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.1.1.1", qMsg.Question[0].Name))
		respMsg.Answer = append(respMsg.Answer, rr)

		packed, err := respMsg.Pack()
		if err != nil {
			http.Error(w, "pack failed", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/dns-message")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(packed)
	})

	// 显式监听 UDP，便于拿到真实端口并避免与其它测试争用
	udpConn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0})
	if err != nil {
		t.Fatalf("listen mock doh3 udp: %v", err)
	}

	srv := &http3.Server{
		TLSConfig: &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS13,
		},
		QUICConfig: &quic.Config{Allow0RTT: false},
		Handler:    mux,
	}

	go func() { _ = srv.Serve(udpConn) }()

	addr := udpConn.LocalAddr().String()
	return fmt.Sprintf("https://%s/dns-query", addr), func() {
		_ = srv.Close()
		_ = udpConn.Close()
	}
}

func TestDoH3Resolver_BasicAndRetry(t *testing.T) {
	url, shutdown := startMockDoH3Server(t)
	defer shutdown()

	doh3 := NewDoH3Resolver(nil)
	doh3.SetTLSConfig(&tls.Config{InsecureSkipVerify: true})
	defer doh3.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("doh3.example.com")

	// 首次查询建立 QUIC 连接
	resp1, err := doh3.Exchange(ctx, rawQuery, url)
	if err != nil {
		t.Fatalf("first DoH3 Exchange failed: %v", err)
	}
	var msg1 dns.Msg
	if err := msg1.Unpack(resp1); err != nil {
		t.Fatalf("unpack DoH3 response failed: %v", err)
	}
	if len(msg1.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(msg1.Answer))
	}

	// 二次查询复用同一条 QUIC 连接
	resp2, err := doh3.Exchange(ctx, rawQuery, url)
	if err != nil {
		t.Fatalf("second DoH3 Exchange (reused conn) failed: %v", err)
	}
	var msg2 dns.Msg
	if err := msg2.Unpack(resp2); err != nil {
		t.Fatalf("unpack reused response failed: %v", err)
	}
	if len(msg2.Answer) != 1 {
		t.Fatalf("expected 1 answer on reused conn, got %d", len(msg2.Answer))
	}
}

func TestDoH3Resolver_Errors(t *testing.T) {
	doh3 := NewDoH3Resolver(nil)
	defer doh3.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("err.example.com")

	if _, err := doh3.Exchange(ctx, rawQuery, "   "); err == nil {
		t.Fatal("expected error for empty url, got nil")
	}

	if _, err := doh3.Exchange(ctx, rawQuery, "http://insecure.example/dns-query"); err == nil {
		t.Fatal("expected error for non-https url, got nil")
	}
}

func TestDoH3Resolver_ClosedReturnsError(t *testing.T) {
	url, shutdown := startMockDoH3Server(t)
	defer shutdown()

	doh3 := NewDoH3Resolver(nil)
	doh3.SetTLSConfig(&tls.Config{InsecureSkipVerify: true})

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if _, err := doh3.Exchange(ctx, makeTestDNSQuery("a.example.com"), url); err != nil {
		t.Fatalf("initial exchange failed: %v", err)
	}

	if err := doh3.Close(); err != nil {
		t.Fatalf("close doh3: %v", err)
	}

	if _, err := doh3.Exchange(ctx, makeTestDNSQuery("b.example.com"), url); err == nil {
		t.Fatal("expected error after Close, got nil")
	}
}

func TestDoH3ProtocolParsing(t *testing.T) {
	for _, in := range []string{"DOH3", "doh3", "H3", "h3"} {
		if got := ParseProtocol(in); got != ProtocolDoH3 {
			t.Errorf("ParseProtocol(%q) = %q, want %q", in, got, ProtocolDoH3)
		}
		if !IsValidProtocol(in) {
			t.Errorf("IsValidProtocol(%q) = false, want true", in)
		}
	}

	if !ProtocolDoH3.IsEncrypted() {
		t.Error("DOH3 must be encrypted")
	}
	if !ProtocolDoH3.IsHTTPStyleProtocol() {
		t.Error("DOH3 must be treated as an HTTPS-style protocol")
	}
	if ProtocolDoT.IsHTTPStyleProtocol() {
		t.Error("DOT must not be treated as an HTTPS-style protocol")
	}
}
