package dns

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"testing"
	"time"

	"github.com/miekg/dns"
	"github.com/quic-go/quic-go"
)

// doqFixture 是一套跑起来的 DoQ 测试环境。
//
// 证书由服务端与客户端共用同一份：两边各自生成会得到两张不同的自签证书，
// 客户端的信任池就校验不过服务端。
type doqFixture struct {
	pool     *x509.CertPool
	port     int
	server   *Server
	clientID func() string
}

// freeUDPPort 取一个当前空闲的 UDP 端口号
func freeUDPPort(t *testing.T) int {
	t.Helper()
	for attempt := 0; attempt < 100; attempt++ {
		pc, err := net.ListenPacket("udp", "127.0.0.1:0")
		if err != nil {
			time.Sleep(5 * time.Millisecond)
			continue
		}
		port := pc.LocalAddr().(*net.UDPAddr).Port
		_ = pc.Close()
		return port
	}
	t.Fatalf("取空闲 UDP 端口失败")
	return 0
}

func newDoQFixture(t *testing.T, serverName string) *doqFixture {
	t.Helper()

	serverTLS, pool := dotFixture(t)
	port := freeUDPPort(t)
	capture, clientID := captureClientID()

	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
			resp := new(dns.Msg)
			resp.SetReply(req)
			rr, _ := dns.NewRR(fmt.Sprintf("%s 300 IN A 1.1.1.1", req.Question[0].Name))
			resp.Answer = append(resp.Answer, rr)
			return resp, nil
		},
	}

	addr := findAvailableLocalPort(t)
	server := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
	}, NewPipeline(capture, NewForwardMiddleware(res)))

	server.SetEncryptedConfig(&EncryptedServerConfig{
		DoQEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoQPort:       port,
		ServerName:    serverName,
		TLSConfig:     serverTLS,
	})
	if err := server.Start(); err != nil {
		t.Fatalf("启动失败: %v", err)
	}

	return &doqFixture{pool: pool, port: port, server: server, clientID: clientID}
}

func (f *doqFixture) close() { _ = f.server.Shutdown() }

// dial 建立一条 DoQ 连接；SNI 固定为 dns.lan，因为证书只覆盖这个名字
func (f *doqFixture) dial(t *testing.T) quic.Connection {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	conn, err := quic.DialAddr(ctx,
		fmt.Sprintf("127.0.0.1:%d", f.port),
		&tls.Config{
			RootCAs:    f.pool,
			ServerName: "dns.lan",
			NextProtos: []string{doqALPN},
			MinVersion: tls.VersionTLS13,
		},
		&quic.Config{HandshakeIdleTimeout: 3 * time.Second, MaxIdleTimeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("QUIC 连接失败: %v", err)
	}
	return conn
}

// doqQuery 在一条新流上发一次查询并读回应答
func doqQuery(t *testing.T, conn quic.Connection, name string, msgID uint16) (*dns.Msg, error) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(name), dns.TypeA)
	m.Id = msgID
	packed, err := m.Pack()
	if err != nil {
		t.Fatalf("封装查询失败: %v", err)
	}

	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		return nil, fmt.Errorf("开流失败: %w", err)
	}
	defer func() { _ = stream.Close() }()

	if err := stream.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		return nil, err
	}

	framed := make([]byte, 2+len(packed))
	binary.BigEndian.PutUint16(framed, uint16(len(packed)))
	copy(framed[2:], packed)
	if _, err := stream.Write(framed); err != nil {
		return nil, fmt.Errorf("写出失败: %w", err)
	}

	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(stream, lenBuf); err != nil {
		return nil, fmt.Errorf("读长度失败: %w", err)
	}
	size := int(binary.BigEndian.Uint16(lenBuf))
	if size < 12 {
		return nil, fmt.Errorf("应答长度非法: %d", size)
	}
	buf := make([]byte, size)
	if _, err := io.ReadFull(stream, buf); err != nil {
		return nil, fmt.Errorf("读应答失败: %w", err)
	}

	resp := new(dns.Msg)
	if err := resp.Unpack(buf); err != nil {
		return nil, fmt.Errorf("应答无法解析: %w", err)
	}
	return resp, nil
}

func TestDoQ_ServesQuery(t *testing.T) {
	f := newDoQFixture(t, "dns.lan")
	defer f.close()

	if f.server.DoQListenAddress() == "" {
		t.Fatal("DoQ 已启用时应报告实际监听地址")
	}

	conn := f.dial(t)
	defer func() { _ = conn.CloseWithError(0, "") }()

	resp, err := doqQuery(t, conn, "example.com", 0)
	if err != nil {
		t.Fatalf("DoQ 查询失败: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("应返回一条应答，实得 %d", len(resp.Answer))
	}
	if a, ok := resp.Answer[0].(*dns.A); !ok || a.A.String() != "1.1.1.1" {
		t.Fatalf("应答内容不符: %v", resp.Answer)
	}
	// RFC 9250 §4.2.1：应答的 Message ID 必须为 0
	if resp.Id != 0 {
		t.Fatalf("应答 Message ID 应为 0，实得 %d", resp.Id)
	}
}

// 一条连接上可以连续开多条流，各自独立完成查询
func TestDoQ_MultipleStreamsOnOneConnection(t *testing.T) {
	f := newDoQFixture(t, "dns.lan")
	defer f.close()

	conn := f.dial(t)
	defer func() { _ = conn.CloseWithError(0, "") }()

	for i := 0; i < 3; i++ {
		resp, err := doqQuery(t, conn, fmt.Sprintf("host%d.example.com", i), 0)
		if err != nil {
			t.Fatalf("第 %d 次查询失败: %v", i+1, err)
		}
		if len(resp.Answer) != 1 {
			t.Fatalf("第 %d 条应答数量不符: %d", i+1, len(resp.Answer))
		}
	}
}

// 非 0 的 Message ID 违反 RFC 9250，必须按协议错误处理
func TestDoQ_RejectsNonZeroMessageID(t *testing.T) {
	f := newDoQFixture(t, "dns.lan")
	defer f.close()

	conn := f.dial(t)
	defer func() { _ = conn.CloseWithError(0, "") }()

	if _, err := doqQuery(t, conn, "example.com", 0x1234); err == nil {
		t.Fatal("非 0 Message ID 应被拒绝")
	}
}

// SNI 里的 ClientID 应与 DoT 用同一套规则识别
func TestDoQ_ClientIDFromSNI(t *testing.T) {
	f := newDoQFixture(t, "dns.lan")
	defer f.close()

	// 证书只覆盖 dns.lan，故这里跳过主机名校验、只验证 SNI 的识别路径
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := quic.DialAddr(ctx,
		fmt.Sprintf("127.0.0.1:%d", f.port),
		&tls.Config{
			RootCAs:            f.pool,
			InsecureSkipVerify: true,
			ServerName:         "tablet.dns.lan",
			NextProtos:         []string{doqALPN},
			MinVersion:         tls.VersionTLS13,
		},
		&quic.Config{HandshakeIdleTimeout: 3 * time.Second})
	if err != nil {
		t.Fatalf("QUIC 连接失败: %v", err)
	}
	defer func() { _ = conn.CloseWithError(0, "") }()

	if _, err := doqQuery(t, conn, "example.com", 0); err != nil {
		t.Fatalf("DoQ 查询失败: %v", err)
	}
	if got := f.clientID(); got != "tablet" {
		t.Fatalf("SNI 里的 ClientID 应为 tablet，实得 %q", got)
	}
}

// 未启用 DoQ 时不应占用端口
func TestDoQ_NotStartedWhenDisabled(t *testing.T) {
	port := freeUDPPort(t)
	addr := findAvailableLocalPort(t)

	serverTLS, pool := dotFixture(t)
	srv := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
	}, NewPipeline())
	srv.SetEncryptedConfig(&EncryptedServerConfig{
		DoQEnabled:    false,
		ListenAddress: "127.0.0.1",
		DoQPort:       port,
		TLSConfig:     serverTLS,
	})
	defer func() { _ = srv.Shutdown() }()

	if srv.DoQListenAddress() != "" {
		t.Fatal("DoQ 未启用时不应报告监听地址")
	}

	// 用一次连接尝试确认端口无人监听：QUIC 上表现为握手失败
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	conn, err := quic.DialAddr(ctx, fmt.Sprintf("127.0.0.1:%d", port),
		&tls.Config{RootCAs: pool, ServerName: "dns.lan", NextProtos: []string{doqALPN}},
		&quic.Config{HandshakeIdleTimeout: time.Second})
	if err == nil {
		_ = conn.CloseWithError(0, "")
		t.Fatal("DoQ 未启用时端口不应接受连接")
	}
}

// 证书不可用时 DoQ 起不来，但明文解析必须照常工作
func TestDoQ_FailureDoesNotBreakPlainDNS(t *testing.T) {
	port := freeUDPPort(t)
	addr := findAvailableLocalPort(t)

	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
			resp := new(dns.Msg)
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
		DoQEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoQPort:       port,
		ServerName:    "dns.lan",
	})
	if err := srv.Start(); err != nil {
		t.Fatalf("明文监听应照常启动: %v", err)
	}
	defer func() { _ = srv.Shutdown() }()

	if srv.DoQListenAddress() != "" {
		t.Fatal("证书缺失时不应报告为已在监听")
	}

	c := new(dns.Client)
	c.Timeout = 2 * time.Second
	m := new(dns.Msg)
	m.SetQuestion("example.com.", dns.TypeA)
	if _, _, err := c.Exchange(m, addr); err != nil {
		t.Fatalf("明文查询失败: %v", err)
	}
}

// 关闭服务必须断开在途 QUIC 连接，否则会留下无法回收的协程
func TestDoQ_ShutdownClosesConnections(t *testing.T) {
	f := newDoQFixture(t, "dns.lan")

	conn := f.dial(t)
	defer func() { _ = conn.CloseWithError(0, "") }()

	if _, err := doqQuery(t, conn, "example.com", 0); err != nil {
		t.Fatalf("DoQ 查询失败: %v", err)
	}

	if err := f.server.Shutdown(); err != nil {
		t.Fatalf("关闭失败: %v", err)
	}

	// 连接上下文应被取消：服务端已不再维护这条连接
	select {
	case <-conn.Context().Done():
	case <-time.After(3 * time.Second):
		t.Fatal("关闭后 QUIC 连接应被断开")
	}
}

func TestReadDoQQuery(t *testing.T) {
	// 长度为 0 的报文在协议上不成立
	if _, err := readDoQQuery(bytes.NewReader([]byte{0, 0})); !errors.Is(err, errDoQProtocol) {
		t.Fatalf("零长度报文应判为协议错误，实得 %v", err)
	}

	// 长度前缀声称 100 字节但实际只有 2 字节：属于正常截断而非协议错误
	short := []byte{0, 100, 1, 2}
	err := func() error {
		_, e := readDoQQuery(bytes.NewReader(short))
		return e
	}()
	if err == nil {
		t.Fatal("长度与实际不符时应报错")
	}
	if errors.Is(err, errDoQProtocol) {
		t.Fatal("数据被截断不应判为协议错误")
	}
}

// 长度前缀声称 65535 字节却没有后续数据：属于截断，不该被当成合法查询
func TestReadDoQQueryTruncatedBody(t *testing.T) {
	if _, err := readDoQQuery(bytes.NewReader([]byte{0xFF, 0xFF})); err == nil {
		t.Fatal("正文与声明长度不符时应报错")
	}
}
