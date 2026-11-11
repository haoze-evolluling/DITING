package core

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/binary"
	"fmt"
	"io"
	"math/big"
	"net"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func generateTestTLSCert(t *testing.T) tls.Certificate {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate rsa key: %v", err)
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization: []string{"Diting Test"},
			CommonName:   "127.0.0.1",
		},
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		DNSNames:              []string{"localhost"},
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		t.Fatalf("create cert: %v", err)
	}

	return tls.Certificate{
		Certificate: [][]byte{derBytes},
		PrivateKey:  priv,
	}
}

func startMockDoTServer(t *testing.T) (net.Listener, string) {
	cert := generateTestTLSCert(t)
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
	}

	listener, err := tls.Listen("tcp", "127.0.0.1:0", tlsConfig)
	if err != nil {
		t.Fatalf("listen mock dot: %v", err)
	}

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go handleDoTConn(conn)
		}
	}()

	return listener, listener.Addr().String()
}

func handleDoTConn(conn net.Conn) {
	defer conn.Close()
	lenBuf := make([]byte, 2)
	for {
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			return
		}
		qLen := binary.BigEndian.Uint16(lenBuf)
		query := make([]byte, qLen)
		if _, err := io.ReadFull(conn, query); err != nil {
			return
		}

		var qMsg dns.Msg
		if err := qMsg.Unpack(query); err != nil {
			return
		}

		respMsg := new(dns.Msg)
		respMsg.SetReply(&qMsg)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.1.1.1", qMsg.Question[0].Name))
		respMsg.Answer = append(respMsg.Answer, rr)

		respBytes, err := respMsg.Pack()
		if err != nil {
			return
		}

		binary.BigEndian.PutUint16(lenBuf, uint16(len(respBytes)))
		if _, err := conn.Write(lenBuf); err != nil {
			return
		}
		if _, err := conn.Write(respBytes); err != nil {
			return
		}
	}
}

func TestDoTResolver_BasicAndPool(t *testing.T) {
	listener, addr := startMockDoTServer(t)
	defer listener.Close()

	dot := NewDoTResolver(nil)
	dot.SetTLSConfig(&tls.Config{
		InsecureSkipVerify: true,
	})
	defer dot.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("dot.example.com")

	// 首次查询创建连接并加入连接池
	resp1, err := dot.Exchange(ctx, rawQuery, addr)
	if err != nil {
		t.Fatalf("first DoT Exchange failed: %v", err)
	}

	var respMsg1 dns.Msg
	if err := respMsg1.Unpack(resp1); err != nil {
		t.Fatalf("unpack DoT response failed: %v", err)
	}
	if len(respMsg1.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(respMsg1.Answer))
	}

	// 二次查询应复用池化连接
	resp2, err := dot.Exchange(ctx, rawQuery, addr)
	if err != nil {
		t.Fatalf("second DoT Exchange (pooled) failed: %v", err)
	}
	var respMsg2 dns.Msg
	if err := respMsg2.Unpack(resp2); err != nil {
		t.Fatalf("unpack pooled response failed: %v", err)
	}
	if len(respMsg2.Answer) != 1 {
		t.Fatalf("expected 1 answer from pooled conn, got %d", len(respMsg2.Answer))
	}

	// 关闭后请求应被拒绝
	_ = dot.Close()
	_, err = dot.Exchange(ctx, rawQuery, addr)
	if err == nil {
		t.Fatalf("expected error after dot.Close, got nil")
	}
}
