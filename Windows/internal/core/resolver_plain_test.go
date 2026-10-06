package core

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func makeTestDNSQuery(domain string) []byte {
	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(domain), dns.TypeA)
	m.RecursionDesired = true
	b, _ := m.Pack()
	return b
}

func startMockDualServer(t *testing.T, handler dns.HandlerFunc) (shutdown func(), udpAddr, tcpAddr string) {
	var tcpL net.Listener
	var pc net.PacketConn
	var err error

	for attempt := 0; attempt < 10; attempt++ {
		tcpL, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			continue
		}
		addr := tcpL.Addr().String()
		pc, err = net.ListenPacket("udp", addr)
		if err == nil {
			break
		}
		_ = tcpL.Close()
	}

	if pc == nil || tcpL == nil {
		t.Fatalf("failed to bind dual server on same port after retries: %v", err)
	}

	addr := tcpL.Addr().String()
	udpAddr = addr
	tcpAddr = addr

	udpSrv := &dns.Server{PacketConn: pc, Handler: handler}
	tcpSrv := &dns.Server{Listener: tcpL, Handler: handler}

	go func() { _ = udpSrv.ActivateAndServe() }()
	go func() { _ = tcpSrv.ActivateAndServe() }()

	shutdown = func() {
		_ = udpSrv.Shutdown()
		_ = tcpSrv.Shutdown()
	}
	return shutdown, udpAddr, tcpAddr
}

func TestPlainResolver_BasicUDP(t *testing.T) {
	shutdown, addr, _ := startMockDualServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.2.3.4", r.Question[0].Name))
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	})
	defer shutdown()

	plain := NewPlainResolver(nil)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("example.com")
	resp, err := plain.Exchange(ctx, rawQuery, addr)
	if err != nil {
		t.Fatalf("plain Exchange failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack plain response failed: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer record, got %d", len(respMsg.Answer))
	}
}

func TestPlainResolver_TruncatedFallbackTCP(t *testing.T) {
	shutdown, addr, _ := startMockDualServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)

		// 若为 UDP 请求，设置 Truncated 标志并不返回 Answer
		if _, isTCP := w.RemoteAddr().(*net.TCPAddr); !isTCP {
			m.Truncated = true
			_ = w.WriteMsg(m)
			return
		}

		// 若为 TCP 请求，完整返回多条 A 记录
		for i := 1; i <= 5; i++ {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 10.0.0.%d", r.Question[0].Name, i))
			m.Answer = append(m.Answer, rr)
		}
		_ = w.WriteMsg(m)
	})
	defer shutdown()

	plain := NewPlainResolver(nil)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("large.example.com")
	resp, err := plain.Exchange(ctx, rawQuery, addr)
	if err != nil {
		t.Fatalf("expected truncated query to fallback to TCP successfully: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack plain response failed: %v", err)
	}
	if respMsg.Truncated {
		t.Fatalf("response should not be truncated after TCP fallback")
	}
	if len(respMsg.Answer) != 5 {
		t.Fatalf("expected 5 answer records from TCP fallback, got %d", len(respMsg.Answer))
	}
}

func TestPlainResolver_BootstrapResolution(t *testing.T) {
	shutdown, addr, _ := startMockDualServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 8.8.8.8", r.Question[0].Name))
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	})
	defer shutdown()

	_, port, err := net.SplitHostPort(addr)
	if err != nil {
		t.Fatalf("split host port: %v", err)
	}

	// 构造 bootstrap 解析器，将 "custom-dns.local" 解析到 127.0.0.1
	mockBS, bsAddr := startMockDNSServer(t, func(w dns.ResponseWriter, r *dns.Msg) {
		m := new(dns.Msg)
		m.SetReply(r)
		rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 127.0.0.1", r.Question[0].Name))
		m.Answer = append(m.Answer, rr)
		_ = w.WriteMsg(m)
	})
	defer mockBS.Shutdown()

	bs := NewBootstrapResolver(BootstrapConfig{
		Enabled: true,
		Servers: []BootstrapServer{{ID: "bs", Address: bsAddr}},
	})

	plain := NewPlainResolver(bs)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	rawQuery := makeTestDNSQuery("bootstrap.example.com")
	resp, err := plain.Exchange(ctx, rawQuery, "custom-dns.local:"+port)
	if err != nil {
		t.Fatalf("plain Exchange with bootstrap hostname failed: %v", err)
	}

	var respMsg dns.Msg
	if err := respMsg.Unpack(resp); err != nil {
		t.Fatalf("unpack failed: %v", err)
	}
	if len(respMsg.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %d", len(respMsg.Answer))
	}
}

func TestPlainResolver_TimeoutContext(t *testing.T) {
	// 创建一个黑洞 UDP 监听器（不响应任何数据）
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen blackhole: %v", err)
	}
	defer pc.Close()

	plain := NewPlainResolver(nil)
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	rawQuery := makeTestDNSQuery("timeout.example.com")
	_, err = plain.Exchange(ctx, rawQuery, pc.LocalAddr().String())
	if err == nil {
		t.Fatalf("expected timeout error, got nil")
	}
}
