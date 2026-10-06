package dns

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	miekgdns "github.com/miekg/dns"
)

func findAvailableLocalPort(t *testing.T) string {
	for attempt := 0; attempt < 10; attempt++ {
		l, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			continue
		}
		addr := l.Addr().String()
		_ = l.Close()

		// 检查 UDP 也可以绑定该端口
		pc, err := net.ListenPacket("udp", addr)
		if err == nil {
			_ = pc.Close()
			return addr
		}
	}
	t.Fatalf("failed to find available dual port")
	return ""
}

func TestServer_DualStackQueries(t *testing.T) {
	addr := findAvailableLocalPort(t)

	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
			resp := new(miekgdns.Msg)
			resp.SetReply(req)
			rr, _ := miekgdns.NewRR(fmt.Sprintf("%s 300 IN A 1.1.1.1", req.Question[0].Name))
			resp.Answer = append(resp.Answer, rr)
			return resp, nil
		},
	}

	pipeline := NewPipeline(NewForwardMiddleware(res))
	cfg := ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
	}

	server := NewServer(cfg, pipeline)
	if err := server.Start(); err != nil {
		t.Fatalf("server start failed: %v", err)
	}
	defer func() { _ = server.Shutdown() }()

	// 重复调用 Start 报错
	if err := server.Start(); err == nil {
		t.Fatalf("expected error on duplicate server start, got nil")
	}

	time.Sleep(50 * time.Millisecond)

	// 1. 测试 UDP 查询
	udpClient := &miekgdns.Client{Net: "udp", Timeout: 2 * time.Second}
	reqUDP := new(miekgdns.Msg)
	reqUDP.SetQuestion("udp.example.com.", miekgdns.TypeA)
	reqUDP.Id = 1234
	reqUDP.RecursionDesired = true

	respUDP, _, err := udpClient.Exchange(reqUDP, addr)
	if err != nil {
		t.Fatalf("UDP exchange failed: %v", err)
	}
	if respUDP.Id != 1234 {
		t.Fatalf("mismatched UDP response ID: expected 1234, got %d", respUDP.Id)
	}
	if len(respUDP.Answer) != 1 {
		t.Fatalf("expected 1 answer in UDP response, got %d", len(respUDP.Answer))
	}

	// 2. 测试 TCP 查询
	tcpClient := &miekgdns.Client{Net: "tcp", Timeout: 2 * time.Second}
	reqTCP := new(miekgdns.Msg)
	reqTCP.SetQuestion("tcp.example.com.", miekgdns.TypeA)
	reqTCP.Id = 5678
	reqTCP.RecursionDesired = true

	respTCP, _, err := tcpClient.Exchange(reqTCP, addr)
	if err != nil {
		t.Fatalf("TCP exchange failed: %v", err)
	}
	if respTCP.Id != 5678 {
		t.Fatalf("mismatched TCP response ID: expected 5678, got %d", respTCP.Id)
	}
	if len(respTCP.Answer) != 1 {
		t.Fatalf("expected 1 answer in TCP response, got %d", len(respTCP.Answer))
	}

	// 3. 测试优雅退出
	if err := server.Shutdown(); err != nil {
		t.Fatalf("server shutdown failed: %v", err)
	}
}

func TestServer_DefaultConfig(t *testing.T) {
	cfg := DefaultServerConfig()
	if len(cfg.UDPAddresses) != 2 || len(cfg.TCPAddresses) != 2 {
		t.Fatalf("unexpected default addresses count: %+v", cfg)
	}

	srv := NewServer(ServerConfig{}, NewPipeline())
	if len(srv.config.UDPAddresses) != 2 {
		t.Fatalf("expected fallback to default config when empty")
	}
}

func TestIsIPv6(t *testing.T) {
	if !isIPv6("[::1]:53") {
		t.Fatalf("expected [::1]:53 to be recognized as IPv6")
	}
	if !isIPv6("::1") {
		t.Fatalf("expected ::1 to be recognized as IPv6")
	}
	if isIPv6("127.0.0.1:53") {
		t.Fatalf("expected 127.0.0.1:53 to not be IPv6")
	}
	if isIPv6("127.0.0.1") {
		t.Fatalf("expected 127.0.0.1 to not be IPv6")
	}
	if isIPv6("invalid") {
		t.Fatalf("expected invalid to not be IPv6")
	}
}

type dummyResponseWriter struct {
	remoteAddr net.Addr
	writtenMsg *miekgdns.Msg
}

func (d *dummyResponseWriter) LocalAddr() net.Addr       { return &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 53} }
func (d *dummyResponseWriter) RemoteAddr() net.Addr      { return d.remoteAddr }
func (d *dummyResponseWriter) WriteMsg(m *miekgdns.Msg) error { d.writtenMsg = m; return nil }
func (d *dummyResponseWriter) Write(b []byte) (int, error)    { return len(b), nil }
func (d *dummyResponseWriter) Close() error              { return nil }
func (d *dummyResponseWriter) TsigStatus() error         { return nil }
func (d *dummyResponseWriter) TsigTimersOnly(bool)       {}
func (d *dummyResponseWriter) Hijack()                   {}

func TestServer_ClosedServeDNS(t *testing.T) {
	srv := NewServer(ServerConfig{}, nil)
	srv.closed.Store(true)

	w := &dummyResponseWriter{remoteAddr: &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 12345}}
	req := new(miekgdns.Msg)
	req.SetQuestion("test.example.com.", miekgdns.TypeA)

	srv.ServeDNS(w, req)
	if w.writtenMsg == nil || w.writtenMsg.Rcode != miekgdns.RcodeServerFailure {
		t.Fatalf("expected SERVFAIL when server closed, got: %v", w.writtenMsg)
	}
}

func TestServer_EndToEndRealResolution(t *testing.T) {
	addr := findAvailableLocalPort(t)

	coreResolver, err := core.NewResolver(core.ResolverConfig{
		Mode: core.ModePrimaryBackup,
		Providers: []core.ProviderConfig{
			{ID: "ali", Protocol: core.ProtocolPlain, Server: "223.5.5.5:53"},
			{ID: "dnspod", Protocol: core.ProtocolPlain, Server: "119.29.29.29:53"},
		},
		Bootstrap: core.BootstrapConfig{Enabled: false},
	})
	if err != nil {
		t.Fatalf("core.NewResolver failed: %v", err)
	}
	defer func() { _ = coreResolver.Shutdown() }()

	metricsExecuted := false
	metricsMw := NewMetricsMiddleware(func(ctx *DNSContext, duration time.Duration, mErr error) {
		metricsExecuted = true
		if mErr != nil {
			t.Logf("metrics error: %v", mErr)
		}
	})

	pipeline := NewPipeline(metricsMw, NewForwardMiddleware(coreResolver))

	cfg := ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
	}

	srv := NewServer(cfg, pipeline)
	if err := srv.Start(); err != nil {
		t.Fatalf("srv.Start failed: %v", err)
	}
	defer func() { _ = srv.Shutdown() }()

	time.Sleep(50 * time.Millisecond)

	// 使用 miekgdns.Client 模拟 DNS 客户端发送 www.bing.com A 记录查询
	client := &miekgdns.Client{Net: "udp", Timeout: 4 * time.Second, UDPSize: miekgdns.MaxMsgSize}
	req := new(miekgdns.Msg)
	req.SetQuestion("www.bing.com.", miekgdns.TypeA)
	req.Id = 4321
	req.RecursionDesired = true

	resp, _, err := client.Exchange(req, addr)
	if err != nil {
		t.Fatalf("client.Exchange failed: %v", err)
	}

	if resp.Id != 4321 {
		t.Fatalf("mismatched response ID: expected 4321, got %d", resp.Id)
	}
	if resp.Rcode != miekgdns.RcodeSuccess {
		t.Fatalf("expected RcodeSuccess (0), got %d (%s)", resp.Rcode, miekgdns.RcodeToString[resp.Rcode])
	}
	if len(resp.Answer) == 0 {
		t.Fatalf("expected at least 1 answer record for www.bing.com, got 0")
	}
	if !metricsExecuted {
		t.Fatalf("expected metrics middleware executed")
	}

	t.Logf("Successfully resolved www.bing.com A record via Server pipeline: %d answers", len(resp.Answer))

	// 也测试 AAAA 查询
	reqAAAA := new(miekgdns.Msg)
	reqAAAA.SetQuestion("www.bing.com.", miekgdns.TypeAAAA)
	reqAAAA.Id = 4322
	reqAAAA.RecursionDesired = true

	respAAAA, _, err := client.Exchange(reqAAAA, addr)
	if err != nil {
		t.Fatalf("client.Exchange AAAA failed: %v", err)
	}
	if respAAAA.Rcode != miekgdns.RcodeSuccess {
		t.Fatalf("expected RcodeSuccess for AAAA, got %d", respAAAA.Rcode)
	}
	t.Logf("Successfully resolved www.bing.com AAAA record via Server pipeline: %d answers", len(respAAAA.Answer))
}
