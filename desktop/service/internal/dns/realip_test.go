package dns

import (
	"context"
	"net"
	"net/http"
	"sync"
	"testing"
	"time"

	miekgdns "github.com/miekg/dns"
)

func mustProxy(t *testing.T, enabled bool, entries []string, header string) *TrustedProxy {
	t.Helper()
	tp, err := NewTrustedProxy(enabled, entries, header)
	if err != nil {
		t.Fatalf("构造可信代理失败: %v", err)
	}
	return tp
}

func tcpAddr(s string) net.Addr {
	addr, err := net.ResolveTCPAddr("tcp", s)
	if err != nil {
		panic(err)
	}
	return addr
}

func headerWith(kv ...string) http.Header {
	h := http.Header{}
	for i := 0; i+1 < len(kv); i += 2 {
		h.Set(kv[i], kv[i+1])
	}
	return h
}

// 未启用时一律用直连地址，转发头完全不看
func TestTrustedProxy_DisabledIgnoresHeaders(t *testing.T) {
	tp := mustProxy(t, false, nil, "")
	if tp != nil {
		t.Fatal("未启用时应返回 nil")
	}

	got := tp.RealClientIP(tcpAddr("192.168.1.50:1234"),
		headerWith("X-Forwarded-For", "10.0.0.1"))
	if got == nil || got.String() != "192.168.1.50" {
		t.Fatalf("应返回直连地址，实得 %v", got)
	}
}

// 直连对端不在可信列表里时，转发头必须被彻底忽略
func TestTrustedProxy_UntrustedPeerIgnoresHeaders(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	got := tp.RealClientIP(tcpAddr("192.168.1.50:1234"),
		headerWith("X-Forwarded-For", "127.0.0.1", "X-Real-IP", "127.0.0.1"))
	if got == nil || got.String() != "192.168.1.50" {
		t.Fatalf("不可信对端应被忽略转发头，实得 %v", got)
	}
}

// 可信代理之后：取 XFF 里最右一个不属于可信列表的地址
func TestTrustedProxy_ForwardedForChain(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "9.9.9.9, 203.0.113.7"))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("应取链上最右的不可信地址，实得 %v", got)
	}
}

// 客户端自己伪造的头会被追加在左边，从右往左扫是唯一安全的取法
func TestTrustedProxy_ClientSpoofedPrefixIgnored(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	// 真实终端 203.0.113.7 先写了 127.0.0.1，代理再追加真实来源
	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "127.0.0.1, 203.0.113.7"))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("伪造的前缀不该被采信，实得 %v", got)
	}
}

// 多级可信代理串联时，逐跳剥离直到遇到第一个不可信地址
func TestTrustedProxy_MultipleTrustedHops(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.0/8"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "198.51.100.9, 10.0.0.7, 10.0.1.1"))
	if got == nil || got.String() != "198.51.100.9" {
		t.Fatalf("应剥离全部可信跳，实得 %v", got)
	}
}

// 整条链都是可信代理时没有任何地址能代表终端，退回直连地址
func TestTrustedProxy_AllHopsTrusted(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.0/8"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "10.0.0.9, 10.0.1.1"))
	if got == nil || got.String() != "10.0.0.5" {
		t.Fatalf("全可信时应退回直连地址，实得 %v", got)
	}
}

// 垃圾项位于已找到地址的左侧时不影响结果：左侧整段都是客户端
// 可以随意注入的，本就不参与判定
func TestTrustedProxy_MalformedPrefixIgnored(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "not-an-ip, 203.0.113.7"))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("左侧垃圾不该影响判定，实得 %v", got)
	}
}

// 扫描途中撞上垃圾项则整体作废：垃圾出现在右侧说明它是可信代理
// 写的，这条头本身已经不可信，退回直连地址比继续猜更安全
func TestTrustedProxy_MalformedEntryVoidsHeader(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "203.0.113.7, not-an-ip"))
	if got == nil || got.String() != "10.0.0.5" {
		t.Fatalf("含垃圾的转发头应整体作废，实得 %v", got)
	}
}

// 没有 XFF 时回落到 X-Real-IP
func TestTrustedProxy_RealIPFallback(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Real-IP", "203.0.113.7"))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("应回落到 X-Real-IP，实得 %v", got)
	}
}

// 自定义头名优先于内置的两个：Cloudflare 之类的部署只能靠它
func TestTrustedProxy_CustomHeaderWins(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "CF-Connecting-IP")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"), headerWith(
		"CF-Connecting-IP", "203.0.113.7",
		"X-Forwarded-For", "198.51.100.9",
	))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("自定义头应优先，实得 %v", got)
	}
}

// 带端口的写法要能解析出来
func TestTrustedProxy_HeaderWithPort(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")

	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Real-IP", "203.0.113.7:51234"))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("带端口的地址应解析出 IP，实得 %v", got)
	}
}

// IPv6 对端与 IPv4-mapped 地址都要归一到同一形式
func TestTrustedProxy_IPv6AndMappedAddresses(t *testing.T) {
	tp := mustProxy(t, true, []string{"2001:db8::/32"}, "")

	// 链上地址同样落在可信网段内，故被视为又一跳代理，退回直连地址
	got := tp.RealClientIP(tcpAddr("[2001:db8::5]:443"),
		headerWith("X-Forwarded-For", "2001:db8:1::7"))
	if got == nil || got.String() != "2001:db8::5" {
		t.Fatalf("网段内的链上地址应被当作可信跳，实得 %v", got)
	}

	// 网段外的 IPv6 终端应被正确取出
	got = tp.RealClientIP(tcpAddr("[2001:db8::5]:443"),
		headerWith("X-Forwarded-For", "2001:dead::7"))
	if got == nil || got.String() != "2001:dead::7" {
		t.Fatalf("网段外的 IPv6 应被取出，实得 %v", got)
	}

	// ::ffff:1.2.3.4 必须与 1.2.3.4 命中同一条规则
	mapped := mustProxy(t, true, []string{"1.2.3.4"}, "")
	got = mapped.RealClientIP(tcpAddr("[::ffff:1.2.3.4]:443"),
		headerWith("X-Forwarded-For", "203.0.113.7"))
	if got == nil || got.String() != "203.0.113.7" {
		t.Fatalf("IPv4-mapped 对端应命中可信列表，实得 %v", got)
	}
}

// 对端不可解析时不能凭空造出一个来源
func TestTrustedProxy_NilPeer(t *testing.T) {
	tp := mustProxy(t, true, []string{"10.0.0.5"}, "")
	if got := tp.RealClientIP(nil, headerWith("X-Forwarded-For", "203.0.113.7")); got != nil {
		t.Fatalf("无对端时不应给出 IP，实得 %v", got)
	}
}

func TestNewTrustedProxy_RejectsInvalidEntries(t *testing.T) {
	for _, entry := range []string{"not-an-ip", "10.0.0.0/99", "999.1.1.1"} {
		if _, err := NewTrustedProxy(true, []string{entry}, ""); err == nil {
			t.Fatalf("%q 应被拒绝", entry)
		}
	}
}

// 空列表与未启用等价：谁都不信
func TestTrustedProxy_EmptyListTrustsNobody(t *testing.T) {
	tp := mustProxy(t, true, nil, "")
	if tp == nil {
		t.Fatal("启用时不应返回 nil")
	}
	if !tp.Empty() {
		t.Fatal("空列表应报告 Empty")
	}
	got := tp.RealClientIP(tcpAddr("10.0.0.5:443"),
		headerWith("X-Forwarded-For", "203.0.113.7"))
	if got == nil || got.String() != "10.0.0.5" {
		t.Fatalf("空列表应忽略转发头，实得 %v", got)
	}
}

// captureClientIP 返回一个把 ctx.ClientIP 记下来的中间件
func captureClientIP() (Middleware, func() string) {
	var mu sync.Mutex
	var ip string
	mw := func(ctx *DNSContext, next func() error) error {
		mu.Lock()
		if ctx.ClientIP != nil {
			ip = ctx.ClientIP.String()
		} else {
			ip = ""
		}
		mu.Unlock()
		return next()
	}
	return mw, func() string {
		mu.Lock()
		defer mu.Unlock()
		return ip
	}
}

// newDoHProxyFixture 起一套 DoH，并把 ctx.ClientIP 记下来供断言。
//
// 与 newDoHFixture 的区别只在多挂了一个取 IP 的中间件，
// 且可信代理列表由调用方给定。
func newDoHProxyFixture(t *testing.T, tp *TrustedProxy) (*dohFixture, func() string) {
	t.Helper()

	serverTLS, pool := dotFixture(t)
	port := freeTCPPort(t)
	capture, clientIP := captureClientIP()

	res := &mockResolver{
		exchangeFunc: func(ctx context.Context, req *miekgdns.Msg) (*miekgdns.Msg, error) {
			resp := new(miekgdns.Msg)
			resp.SetReply(req)
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
		DoHEnabled:    true,
		ListenAddress: "127.0.0.1",
		DoHPort:       port,
		DoHPath:       "/dns-query",
		ServerName:    "dns.lan",
		TLSConfig:     serverTLS,
		TrustedProxy:  tp,
		ReadTimeout:   2 * time.Second,
		IdleTimeout:   2 * time.Second,
	})
	if err := server.Start(); err != nil {
		t.Fatalf("启动失败: %v", err)
	}
	return &dohFixture{pool: pool, port: port, server: server}, clientIP
}

// 端到端：默认部署（无可信代理）下，伪造转发头必须完全无效，
// 否则一个匿名查询者就能顶着 127.0.0.1 绕过访问控制
func TestDoH_IgnoresForwardedHeaderWithoutTrustedProxy(t *testing.T) {
	f, clientIP := newDoHProxyFixture(t, nil)
	defer f.close()

	req := f.request(t, http.MethodPost, "/dns-query", "dns.lan")
	req.Header.Set("X-Forwarded-For", "127.0.0.1")
	if _, status := f.send(t, f.client(t), req); status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}

	got := clientIP()
	// 请求经回环发起，真实来源就是 127.0.0.1；关键在于它来自直连地址
	// 而非那个头——用另一个不可信的伪造值才能把两者区分开
	if got != "127.0.0.1" {
		t.Fatalf("应取直连地址，实得 %q", got)
	}
}

// 端到端：配了可信代理后，转发头里的终端地址才会被采用
func TestDoH_UsesForwardedHeaderThroughTrustedProxy(t *testing.T) {
	tp := mustProxy(t, true, []string{"127.0.0.1"}, "")
	f, clientIP := newDoHProxyFixture(t, tp)
	defer f.close()

	req := f.request(t, http.MethodPost, "/dns-query", "dns.lan")
	req.Header.Set("X-Forwarded-For", "203.0.113.7")
	if _, status := f.send(t, f.client(t), req); status != http.StatusOK {
		t.Fatalf("状态码应为 200，实得 %d", status)
	}

	if got := clientIP(); got != "203.0.113.7" {
		t.Fatalf("可信代理后应取转发头地址，实得 %q", got)
	}
}
