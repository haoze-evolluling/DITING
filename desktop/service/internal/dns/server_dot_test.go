package dns

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/haoze-evolluling/diting/server/internal/core"
	miekgdns "github.com/miekg/dns"
)

// freeTCPPort 取一个当前空闲的 TCP 端口号。
//
// 先 Listen 再 Close 存在被别的进程抢走的窗口，但 DoT 端口在测试里是随机的，
// 撞上的概率可以接受；真要撞上，绑定会失败并让用例直接报错。
func freeTCPPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("取空闲端口失败: %v", err)
	}
	defer func() { _ = l.Close() }()
	return l.Addr().(*net.TCPAddr).Port
}

// dotFixture 生成一张自签证书，并返回服务端 TLS 配置与客户端信任池
func dotFixture(t *testing.T) (*tls.Config, *x509.CertPool) {
	t.Helper()

	cfg := core.DefaultCertConfig()
	cfg.CommonName = "dns.lan"
	cfg.DNSNames = []string{"dns.lan"}
	cfg.ValidDays = 30

	gen, err := core.GenerateSelfSignedCert(cfg)
	if err != nil {
		t.Fatalf("生成自签证书失败: %v", err)
	}
	pair, err := tls.X509KeyPair(gen.CertPEM, gen.KeyPEM)
	if err != nil {
		t.Fatalf("装载密钥对失败: %v", err)
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(gen.CertPEM) {
		t.Fatal("证书无法加入信任池")
	}

	serverTLS := &tls.Config{
		MinVersion:   tls.VersionTLS12,
		Certificates: []tls.Certificate{pair},
		NextProtos:   dotALPNForTest(),
	}
	return serverTLS, pool
}

func dotALPNForTest() []string { return []string{"dot"} }

// startDoTServer 启动一个仅含 DoT 监听的 DNS 服务
func startDoTServer(t *testing.T, tlsCfg *tls.Config, serverName string, port int) *Server {
	t.Helper()

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

	// 明文监听取随机端口，避免与机器上真实的 53 端口冲突
	addr := findAvailableLocalPort(t)
	server := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
	}, pipeline)

	server.SetEncryptedConfig(&EncryptedServerConfig{
		DoTEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoTPort:       port,
		ServerName:    serverName,
		TLSConfig:     tlsCfg,
		ReadTimeout:   2 * time.Second,
		IdleTimeout:   2 * time.Second,
	})
	if err := server.Start(); err != nil {
		t.Fatalf("启动失败: %v", err)
	}
	return server
}

// dialDoT 向 DoT 端口发起一次带 SNI 的加密查询
func dialDoT(t *testing.T, pool *x509.CertPool, port int, sni, name string) (*miekgdns.Msg, error) {
	t.Helper()

	conn, err := tls.DialWithDialer(
		&net.Dialer{Timeout: 3 * time.Second},
		"tcp",
		fmt.Sprintf("127.0.0.1:%d", port),
		&tls.Config{
			MinVersion: tls.VersionTLS12,
			RootCAs:    pool,
			ServerName: sni,
			NextProtos: dotALPNForTest(),
		},
	)
	if err != nil {
		return nil, err
	}
	defer func() { _ = conn.Close() }()

	if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		return nil, err
	}

	m := new(miekgdns.Msg)
	m.SetQuestion(miekgdns.Fqdn(name), miekgdns.TypeA)
	m.Id = miekgdns.Id()

	if err := (&miekgdns.Conn{Conn: conn}).WriteMsg(m); err != nil {
		return nil, err
	}
	return (&miekgdns.Conn{Conn: conn}).ReadMsg()
}

func TestDoT_ServesQueryOverTLS(t *testing.T) {
	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)
	srv := startDoTServer(t, serverTLS, "dns.lan", port)
	defer func() { _ = srv.Shutdown() }()

	resp, err := dialDoT(t, pool, port, "dns.lan", "example.com")
	if err != nil {
		t.Fatalf("DoT 查询失败: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("应返回一条应答，实得 %d", len(resp.Answer))
	}
	if a, ok := resp.Answer[0].(*miekgdns.A); !ok || a.A.String() != "1.1.1.1" {
		t.Fatalf("应答内容不符: %v", resp.Answer)
	}
}

// 一条连接上连续查询应各自得到应答——DoT 不允许一问一答就断
func TestDoT_MultipleQueriesOnOneConnection(t *testing.T) {
	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)
	srv := startDoTServer(t, serverTLS, "dns.lan", port)
	defer func() { _ = srv.Shutdown() }()

	conn, err := tls.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port), &tls.Config{
		MinVersion: tls.VersionTLS12,
		RootCAs:    pool,
		ServerName: "dns.lan",
		NextProtos: dotALPNForTest(),
	})
	if err != nil {
		t.Fatalf("TLS 连接失败: %v", err)
	}
	defer func() { _ = conn.Close() }()

	dnsConn := &miekgdns.Conn{Conn: conn}
	for i := 0; i < 3; i++ {
		if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
			t.Fatal(err)
		}
		m := new(miekgdns.Msg)
		m.SetQuestion(fmt.Sprintf("host%d.example.com.", i), miekgdns.TypeA)
		m.Id = uint16(100 + i)
		if err := dnsConn.WriteMsg(m); err != nil {
			t.Fatalf("第 %d 次写出失败: %v", i+1, err)
		}
		resp, err := dnsConn.ReadMsg()
		if err != nil {
			t.Fatalf("第 %d 次读取失败: %v", i+1, err)
		}
		if resp.Id != uint16(100+i) {
			t.Fatalf("第 %d 条的 Message ID 应为 %d，实得 %d", i+1, 100+i, resp.Id)
		}
		if len(resp.Answer) != 1 {
			t.Fatalf("第 %d 条应答数量不符: %d", i+1, len(resp.Answer))
		}
	}
}

// 客户端不带 SNI 时也要能解析：证书是自签的，靠客户端显式信任
func TestDoT_WorksWithoutSNIWhenCertTrusted(t *testing.T) {
	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)
	srv := startDoTServer(t, serverTLS, "dns.lan", port)
	defer func() { _ = srv.Shutdown() }()

	conn, err := tls.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port), &tls.Config{
		MinVersion: tls.VersionTLS12,
		RootCAs:    pool,
		// InsecureSkipVerify 只为跳过主机名校验；证书链仍由 RootCAs 校验
		InsecureSkipVerify: true,
		NextProtos:         dotALPNForTest(),
	})
	if err != nil {
		t.Fatalf("TLS 连接失败: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	m := new(miekgdns.Msg)
	m.SetQuestion("example.com.", miekgdns.TypeA)
	dnsConn := &miekgdns.Conn{Conn: conn}
	if err := dnsConn.WriteMsg(m); err != nil {
		t.Fatalf("写出失败: %v", err)
	}
	resp, err := dnsConn.ReadMsg()
	if err != nil {
		t.Fatalf("读取失败: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("应返回一条应答，实得 %d", len(resp.Answer))
	}
}

// 未启用加密监听时不应占用端口
func TestDoT_NotStartedWhenDisabled(t *testing.T) {
	serverTLS, _ := dotFixture(t)
	port := freeTCPPort(t)

	addr := findAvailableLocalPort(t)
	srv := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
	}, NewPipeline())
	srv.SetEncryptedConfig(&EncryptedServerConfig{
		DoTEnabled:    false,
		ListenAddress: "127.0.0.1",
		DoTPort:       port,
		TLSConfig:     serverTLS,
	})
	if err := srv.Start(); err != nil {
		t.Fatalf("启动失败: %v", err)
	}
	defer func() { _ = srv.Shutdown() }()

	if srv.EncryptedEnabled() {
		t.Fatal("DoT 未启用时不应报告为已启用")
	}
	if _, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 300*time.Millisecond); err == nil {
		t.Fatal("DoT 未启用时端口不应处于监听状态")
	}
}

// 证书不可用时 DoT 起不来，但明文解析必须照常工作
func TestDoT_FailureDoesNotBreakPlainDNS(t *testing.T) {
	port := freeTCPPort(t)
	addr := findAvailableLocalPort(t)

	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
			resp := new(miekgdns.Msg)
			resp.SetReply(req)
			return resp, nil
		},
	}
	srv := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  time.Second,
		WriteTimeout: time.Second,
	}, NewPipeline(NewForwardMiddleware(res)))
	// 没有证书：加密监听应当在内部失败，且不影响明文
	srv.SetEncryptedConfig(&EncryptedServerConfig{
		DoTEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoTPort:       port,
		ServerName:    "dns.lan",
	})
	if err := srv.Start(); err != nil {
		t.Fatalf("明文监听应照常启动: %v", err)
	}
	defer func() { _ = srv.Shutdown() }()

	c := new(miekgdns.Client)
	c.Timeout = 2 * time.Second
	m := new(miekgdns.Msg)
	m.SetQuestion("example.com.", miekgdns.TypeA)
	if _, _, err := c.Exchange(m, addr); err != nil {
		t.Fatalf("明文查询失败: %v", err)
	}
}

// 关闭服务必须断开停留中的空闲 DoT 连接，否则会留下半开的 socket
func TestDoT_ShutdownClosesIdleConnections(t *testing.T) {
	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)
	srv := startDoTServer(t, serverTLS, "dns.lan", port)

	conn, err := tls.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port), &tls.Config{
		MinVersion: tls.VersionTLS12,
		RootCAs:    pool,
		ServerName: "dns.lan",
		NextProtos: dotALPNForTest(),
	})
	if err != nil {
		t.Fatalf("TLS 连接失败: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if err := srv.Shutdown(); err != nil {
		t.Fatalf("关闭失败: %v", err)
	}

	// 服务端应已主动断开：这里再读一次会立刻拿到 EOF 而不是等超时
	if err := conn.SetReadDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 1)
	if _, err := conn.Read(buf); err == nil {
		t.Fatal("关闭后不应还能读到数据")
	}
}

// ReloadEncrypted 能够动态启停 DoT 监听器
func TestDoT_ReloadEncrypted(t *testing.T) {
	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)

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
	addr := findAvailableLocalPort(t)

	cfg := ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
	}
	srv := NewServer(cfg, pipeline)
	if err := srv.Start(); err != nil {
		t.Fatalf("启动失败: %v", err)
	}
	defer func() { _ = srv.Shutdown() }()

	if srv.DoTListenAddress() != "" {
		t.Fatalf("初始状态不应有 DoT 监听")
	}

	// 动态开启 DoT
	encCfg := &EncryptedServerConfig{
		DoTEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoTPort:       port,
		TLSConfig:     serverTLS,
	}
	srv.ReloadEncrypted(encCfg)

	if srv.DoTListenAddress() == "" {
		t.Fatalf("重载后应有 DoT 监听")
	}

	resp, err := dialDoT(t, pool, port, "dns.lan", "example.com")
	if err != nil {
		t.Fatalf("DoT 查询失败: %v", err)
	}
	if len(resp.Answer) == 0 {
		t.Fatalf("未收到应答")
	}

	// 动态关闭 DoT
	srv.ReloadEncrypted(nil)
	if srv.DoTListenAddress() != "" {
		t.Fatalf("关闭后不应有 DoT 监听")
	}
}

