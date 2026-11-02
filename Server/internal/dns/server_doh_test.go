package dns

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	miekgdns "github.com/miekg/dns"
)

// captureClientID 返回一个把 ctx.ClientID 记下来的中间件。
//
// ClientID 是流水线内部状态，HTTP 层看不到；要断言入口识别结果，
// 只能在管线里拦一道。
func captureClientID() (Middleware, func() string) {
	var mu sync.Mutex
	var id string
	mw := func(ctx *DNSContext, next func() error) error {
		mu.Lock()
		id = ctx.ClientID
		mu.Unlock()
		return next()
	}
	return mw, func() string {
		mu.Lock()
		defer mu.Unlock()
		return id
	}
}

// dohFixture 是一套跑起来的 DoH 测试环境。
//
// 证书必须由服务端与客户端共用同一份：各自 dotFixture 会拿到两张不同的
// 自签证书，客户端的信任池就校验不过服务端了。
type dohFixture struct {
	pool     *x509.CertPool
	port     int
	server   *Server
	clientID func() string
}

func newDoHFixture(t *testing.T, serverName, path string) *dohFixture {
	t.Helper()

	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)
	capture, clientID := captureClientID()

	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
			resp := new(miekgdns.Msg)
			resp.SetReply(req)
			rr, _ := miekgdns.NewRR(fmt.Sprintf("%s 300 IN A 1.1.1.1", req.Question[0].Name))
			resp.Answer = append(resp.Answer, rr)
			return resp, nil
		},
	}

	// 明文监听取随机端口，避免与机器上真实的 53 端口冲突
	addr := findAvailableLocalPort(t)
	server := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
	}, NewPipeline(capture, NewForwardMiddleware(res)))

	server.SetEncryptedConfig(&EncryptedServerConfig{
		DoHEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoHPort:       port,
		DoHPath:       path,
		ServerName:    serverName,
		TLSConfig:     serverTLS,
		ReadTimeout:   2 * time.Second,
		IdleTimeout:   2 * time.Second,
	})
	if err := server.Start(); err != nil {
		t.Fatalf("启动失败: %v", err)
	}

	return &dohFixture{pool: pool, port: port, server: server, clientID: clientID}
}

func (f *dohFixture) close() { _ = f.server.Shutdown() }

// client 构造一个信任自签证书、且强制走 HTTP/2 的客户端
func (f *dohFixture) client(t *testing.T) *http.Client {
	t.Helper()
	return &http.Client{
		Timeout: 3 * time.Second,
		Transport: &http.Transport{
			// 设了 TLSClientConfig 后 Go 默认关掉 HTTP/2，这里显式打开，
			// 好让用例跑在真实 DoH 客户端会走的 h2 路径上
			ForceAttemptHTTP2: true,
			TLSClientConfig: &tls.Config{
				MinVersion: tls.VersionTLS12,
				RootCAs:    f.pool,
				ServerName: "dns.lan",
			},
		},
	}
}

func (f *dohFixture) url(path string) string {
	return fmt.Sprintf("https://127.0.0.1:%d%s", f.port, path)
}

// request 构造一次 A 记录查询：GET 走 ?dns=，POST 走正文
func (f *dohFixture) request(t *testing.T, method, path, host string) *http.Request {
	t.Helper()
	m := new(miekgdns.Msg)
	m.SetQuestion("example.com.", miekgdns.TypeA)
	m.Id = 0x1234
	packed, err := m.Pack()
	if err != nil {
		t.Fatalf("封装查询失败: %v", err)
	}

	var req *http.Request
	if method == http.MethodGet {
		req, err = http.NewRequest(method,
			f.url(path)+"?dns="+base64.RawURLEncoding.EncodeToString(packed), nil)
	} else {
		req, err = http.NewRequest(method, f.url(path), bytes.NewReader(packed))
		if err == nil {
			req.Header.Set("Content-Type", dohContentType)
		}
	}
	if err != nil {
		t.Fatalf("构造请求失败: %v", err)
	}
	if host != "" {
		// Host 头必须显式指定：URL 里是回环地址，识别不出服务器名
		req.Host = host
	}
	return req
}

// send 发出请求并返回应答报文与状态码；非 200 时报文为 nil
func (f *dohFixture) send(t *testing.T, client *http.Client, req *http.Request) (*miekgdns.Msg, int) {
	t.Helper()
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("读取应答失败: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, resp.StatusCode
	}
	if ct := resp.Header.Get("Content-Type"); !isDoHContentType(ct) {
		t.Fatalf("应答 Content-Type 应为 %s，实得 %q", dohContentType, ct)
	}
	msg := new(miekgdns.Msg)
	if err := msg.Unpack(body); err != nil {
		t.Fatalf("应答报文无法解析: %v", err)
	}
	return msg, resp.StatusCode
}

func TestDoH_PostServesQuery(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()

	if f.server.DoHListenAddress() == "" {
		t.Fatal("DoH 已启用时应报告实际监听地址")
	}

	msg, status := f.send(t, f.client(t), f.request(t, http.MethodPost, "/dns-query", "dns.lan"))
	if status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}
	if len(msg.Answer) != 1 {
		t.Fatalf("应返回一条应答，实得 %d", len(msg.Answer))
	}
	if a, ok := msg.Answer[0].(*miekgdns.A); !ok || a.A.String() != "1.1.1.1" {
		t.Fatalf("应答内容不符: %v", msg.Answer)
	}
}

func TestDoH_GetWithBase64Param(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()

	msg, status := f.send(t, f.client(t), f.request(t, http.MethodGet, "/dns-query", "dns.lan"))
	if status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}
	if len(msg.Answer) != 1 {
		t.Fatalf("应返回一条应答，实得 %d", len(msg.Answer))
	}
	// 应答必须与查询 ID 对齐，否则客户端会丢弃
	if msg.Id != 0x1234 {
		t.Fatalf("应答 ID 应为 0x1234，实得 %#x", msg.Id)
	}
}

// 自定义路径要按配置生效，而不是死守 /dns-query
func TestDoH_CustomPath(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "resolve")
	defer f.close()

	if got := f.server.DoHPath(); got != "/resolve" {
		t.Fatalf("规范化后的路径应为 /resolve，实得 %q", got)
	}
	if _, status := f.send(t, f.client(t), f.request(t, http.MethodPost, "/resolve", "dns.lan")); status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}
	client := f.client(t)
	if _, status := f.send(t, client, f.request(t, http.MethodPost, "/dns-query", "dns.lan")); status == http.StatusOK {
		t.Fatal("未注册的路径不应返回 200")
	}
}

func TestDoH_PathClientID(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()

	_, status := f.send(t, f.client(t),
		f.request(t, http.MethodPost, "/dns-query/laptop", "dns.lan"))
	if status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}
	if got := f.clientID(); got != "laptop" {
		t.Fatalf("路径 ClientID 应为 laptop，实得 %q", got)
	}
}

// 路径里的 ClientID 优先于 Host：路径是用户逐字填进客户端的，
// 而 Host 往往是客户端自己挑的默认值
func TestDoH_PathClientIDBeatsHost(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()

	_, status := f.send(t, f.client(t),
		f.request(t, http.MethodPost, "/dns-query/laptop", "tablet.dns.lan"))
	if status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}
	if got := f.clientID(); got != "laptop" {
		t.Fatalf("应以路径 ClientID 为准，实得 %q", got)
	}
}

// 没有路径段时回落到 Host，与 DoT 的 SNI 识别保持同一套语义
func TestDoH_ClientIDFromHost(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()

	_, status := f.send(t, f.client(t),
		f.request(t, http.MethodPost, "/dns-query", "tablet.dns.lan"))
	if status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}
	if got := f.clientID(); got != "tablet" {
		t.Fatalf("Host 里的 ClientID 应为 tablet，实得 %q", got)
	}
}

// 非法 ClientID 必须在入口就挡下，否则调用方会以为自己带着生效的身份
func TestDoH_RejectsInvalidPathClientID(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()

	_, status := f.send(t, f.client(t),
		f.request(t, http.MethodPost, "/dns-query/ph_one", "dns.lan"))
	if status != http.StatusBadRequest {
		t.Fatalf("非法 ClientID 应返回 400，实得 %d", status)
	}
}

func TestDoH_RejectsBadRequests(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	defer f.close()
	client := f.client(t)

	// 缺少 ?dns=
	req, err := http.NewRequest(http.MethodGet, f.url("/dns-query"), nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, status := f.send(t, client, req); status != http.StatusBadRequest {
		t.Fatalf("缺少 dns 参数应返回 400，实得 %d", status)
	}

	// base64 不合法
	req, err = http.NewRequest(http.MethodGet, f.url("/dns-query")+"?dns=!!!!", nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, status := f.send(t, client, req); status != http.StatusBadRequest {
		t.Fatalf("非法 base64 应返回 400，实得 %d", status)
	}

	// POST 却给了错的 Content-Type
	req = f.request(t, http.MethodPost, "/dns-query", "dns.lan")
	req.Header.Set("Content-Type", "application/json")
	if _, status := f.send(t, client, req); status != http.StatusBadRequest {
		t.Fatalf("错误 Content-Type 应返回 400，实得 %d", status)
	}

	// POST 正文不是合法 DNS 报文
	req, err = http.NewRequest(http.MethodPost, f.url("/dns-query"), strings.NewReader("not a dns message"))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", dohContentType)
	if _, status := f.send(t, client, req); status != http.StatusBadRequest {
		t.Fatalf("非法报文应返回 400，实得 %d", status)
	}
}

// Content-Type 允许附带 charset 之类的参数（RFC 8484 的常见写法）
func TestDoH_ContentTypeParamsAccepted(t *testing.T) {
	if !isDoHContentType("application/dns-message; charset=utf-8") {
		t.Fatal("带 charset 的媒体类型应被接受")
	}
	if isDoHContentType("") || isDoHContentType("application/json") {
		t.Fatal("不该接受其它媒体类型")
	}
}

func TestNormalizeDoHPath(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", "/dns-query"},
		{"   ", "/dns-query"},
		// 裸斜杠会被 ServeMux 当成通配前缀，必须回落到默认路径
		{"/", "/dns-query"},
		{"///", "/dns-query"},
		{"dns-query", "/dns-query"},
		{"/dns-query", "/dns-query"},
		{"/dns-query/", "/dns-query"},
		{"/dns-query///", "/dns-query"},
		{"/resolve", "/resolve"},
	}
	for _, tc := range cases {
		if got := normalizeDoHPath(tc.in); got != tc.want {
			t.Fatalf("normalizeDoHPath(%q) = %q，期望 %q", tc.in, got, tc.want)
		}
	}
}

// 未启用 DoH 时不应占用端口
func TestDoH_NotStartedWhenDisabled(t *testing.T) {
	port := freeTCPPort(t)
	addr := findAvailableLocalPort(t)
	srv := NewServer(ServerConfig{
		UDPAddresses: []string{addr},
		TCPAddresses: []string{addr},
	}, NewPipeline())
	srv.SetEncryptedConfig(&EncryptedServerConfig{
		DoHEnabled:    false,
		ListenAddress: "127.0.0.1",
		DoHPort:       port,
	})
	defer func() { _ = srv.Shutdown() }()

	if _, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 300*time.Millisecond); err == nil {
		t.Fatal("DoH 未启用时端口不应处于监听状态")
	}
	if srv.DoHListenAddress() != "" {
		t.Fatal("DoH 未启用时不应报告监听地址")
	}
}

// 证书不可用时 DoH 起不来，但明文解析必须照常工作
func TestDoH_FailureDoesNotBreakPlainDNS(t *testing.T) {
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
		DoHEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoHPort:       port,
		ServerName:    "dns.lan",
	})
	if err := srv.Start(); err != nil {
		t.Fatalf("明文监听应照常启动: %v", err)
	}
	defer func() { _ = srv.Shutdown() }()

	if srv.DoHListenAddress() != "" {
		t.Fatal("证书缺失时不应报告为已在监听")
	}

	c := new(miekgdns.Client)
	c.Timeout = 2 * time.Second
	m := new(miekgdns.Msg)
	m.SetQuestion("example.com.", miekgdns.TypeA)
	if _, _, err := c.Exchange(m, addr); err != nil {
		t.Fatalf("明文查询失败: %v", err)
	}
}

// 关闭服务必须释放 DoH 端口，否则下次启动会绑不上
func TestDoH_ShutdownReleasesPort(t *testing.T) {
	f := newDoHFixture(t, "dns.lan", "")
	port := f.port

	if err := f.server.Shutdown(); err != nil {
		t.Fatalf("关闭失败: %v", err)
	}
	if _, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 300*time.Millisecond); err == nil {
		t.Fatal("关闭后端口不应还能连上")
	}

	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Fatalf("关闭后端口应可被重新绑定: %v", err)
	}
	_ = ln.Close()
}
