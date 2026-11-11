package dns

import (
	"fmt"
	"testing"

	"github.com/miekg/dns"
)

// ddrQuery 构造一次 _dns.resolver.arpa. 的查询
func ddrQuery(qtype uint16) *dns.Msg {
	m := new(dns.Msg)
	m.SetQuestion(ddrQueryName, qtype)
	return m
}

// fullDDRAnswer 返回一份「三种协议全开」的广播内容
func fullDDRAnswer() DDRAnswer {
	return DDRAnswer{
		ServerName: "dns.lan",
		DoTEnabled: true,
		DoHEnabled: true,
		DoQEnabled: true,
		DoTPort:    853,
		DoHPort:    443,
		DoQPort:    853,
		DoHPath:    "/dns-query",
		CertHasIPs: true,
	}
}

// svcbAlpn 取一条 SVCB 记录的 alpn 值，取不到时返回空串
func svcbAlpn(rr *dns.SVCB) string {
	for _, kv := range rr.Value {
		if alpn, ok := kv.(*dns.SVCBAlpn); ok && len(alpn.Alpn) > 0 {
			return alpn.Alpn[0]
		}
	}
	return ""
}

// svcbValueOf 取一条 SVCB 记录里指定键的值，便于逐项断言
func svcbValueOf(rr *dns.SVCB, key dns.SVCBKey) string {
	for _, kv := range rr.Value {
		if kv.Key() == key {
			return fmt.Sprint(kv)
		}
	}
	return ""
}

func TestBuildDDRResponse_AllProtocols(t *testing.T) {
	resp := BuildDDRResponse(ddrQuery(dns.TypeSVCB), fullDDRAnswer())
	if resp == nil {
		t.Fatal("应生成应答")
	}
	if resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("Rcode 应为 NOERROR，实得 %d", resp.Rcode)
	}
	if !resp.Authoritative {
		t.Fatal("DDR 应答应由本机权威给出")
	}
	if len(resp.Answer) != 3 {
		t.Fatalf("三种协议应各有一条 SVCB，实得 %d", len(resp.Answer))
	}

	byAlpn := map[string]*dns.SVCB{}
	for _, rr := range resp.Answer {
		svcb, ok := rr.(*dns.SVCB)
		if !ok {
			t.Fatalf("应答类型应为 SVCB，实得 %T", rr)
		}
		if svcb.Hdr.Name != ddrQueryName {
			t.Fatalf("记录名应为 %s，实得 %s", ddrQueryName, svcb.Hdr.Name)
		}
		if svcb.Target != "dns.lan." {
			t.Fatalf("Target 应为服务器名，实得 %s", svcb.Target)
		}
		if svcb.Priority != ddrPriority {
			t.Fatalf("优先级应为 %d，实得 %d", ddrPriority, svcb.Priority)
		}
		if svcb.Hdr.Ttl == 0 {
			t.Fatal("TTL 不应为 0：客户端会反复回查同一个探测")
		}
		byAlpn[svcbAlpn(svcb)] = svcb
	}

	for _, want := range []string{"h2", "dot", "doq"} {
		if byAlpn[want] == nil {
			t.Fatalf("缺少 alpn=%s 的条目", want)
		}
	}

	// DoH 条目必须带 dohpath 模板，且模板里要有查询占位符
	if got := svcbValueOf(byAlpn["h2"], dns.SVCB_DOHPATH); got == "" {
		t.Fatal("DoH 条目应带 dohpath")
	}
	for _, svcb := range byAlpn {
		if svcbValueOf(svcb, dns.SVCB_PORT) == "" {
			t.Fatal("每条记录都应带 port，否则客户端只能猜默认端口")
		}
	}
}

// 证书不含 IP 时不广播 DoT：那些条目的地址来自证书的 IP SAN，
// 证书里没有 IP 就等于声明了一个自己用不了的入口
func TestBuildDDRResponse_SkipsDoTWithoutCertIPs(t *testing.T) {
	answer := fullDDRAnswer()
	answer.CertHasIPs = false

	resp := BuildDDRResponse(ddrQuery(dns.TypeSVCB), answer)
	for _, rr := range resp.Answer {
		if svcbAlpn(rr.(*dns.SVCB)) == "dot" {
			t.Fatal("证书不含 IP 时不应广播 DoT")
		}
	}
	if len(resp.Answer) != 2 {
		t.Fatalf("应只剩 DoH 与 DoQ 两条，实得 %d", len(resp.Answer))
	}
}

// 只有真正在监听的协议才会被广播
func TestBuildDDRResponse_OnlyLiveProtocols(t *testing.T) {
	answer := DDRAnswer{ServerName: "dns.lan", DoHEnabled: true, DoHPort: 8443, DoHPath: "resolve"}
	resp := BuildDDRResponse(ddrQuery(dns.TypeSVCB), answer)

	if len(resp.Answer) != 1 {
		t.Fatalf("应只有一条 DoH 记录，实得 %d", len(resp.Answer))
	}
	svcb := resp.Answer[0].(*dns.SVCB)
	if svcbAlpn(svcb) != "h2" {
		t.Fatalf("应为 DoH 条目，实得 alpn=%q", svcbAlpn(svcb))
	}
	// 路径缺前导斜杠时也要能拼出可用的模板
	if got := svcbValueOf(svcb, dns.SVCB_DOHPATH); got != "/resolve{?dns}" {
		t.Fatalf("dohpath 应被规范化，实得 %q", got)
	}
	// 非默认端口必须写出来，否则客户端会去连 443
	if got := svcbValueOf(svcb, dns.SVCB_PORT); got != "8443" {
		t.Fatalf("端口应为 8443，实得 %q", got)
	}
}

// 没有服务器名就编不出 Target，宁可不广播
func TestBuildDDRResponse_NoServerName(t *testing.T) {
	answer := fullDDRAnswer()
	answer.ServerName = ""

	resp := BuildDDRResponse(ddrQuery(dns.TypeSVCB), answer)
	if len(resp.Answer) != 0 {
		t.Fatalf("缺服务器名时不应有应答记录，实得 %d", len(resp.Answer))
	}
	if resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("仍应是权威 NODATA，实得 Rcode=%d", resp.Rcode)
	}
}

// 非 SVCB 查询返回权威 NODATA，不泄漏给上游
func TestBuildDDRResponse_NonSVCBQuery(t *testing.T) {
	for _, qtype := range []uint16{dns.TypeA, dns.TypeAAAA, dns.TypeTXT} {
		resp := BuildDDRResponse(ddrQuery(qtype), fullDDRAnswer())
		if len(resp.Answer) != 0 {
			t.Fatalf("类型 %d 不应有应答", qtype)
		}
		if resp.Rcode != dns.RcodeSuccess {
			t.Fatalf("类型 %d 应为 NODATA，实得 Rcode=%d", qtype, resp.Rcode)
		}
	}
}

// 非探测名一律不接管
func TestBuildDDRResponse_OtherNames(t *testing.T) {
	m := new(dns.Msg)
	m.SetQuestion("example.com.", dns.TypeSVCB)

	resp := BuildDDRResponse(m, fullDDRAnswer())
	if len(resp.Answer) != 0 {
		t.Fatal("其它名字不应由 DDR 应答")
	}
}

func TestDDRDoHPathTemplate(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", "/dns-query{?dns}"},
		{"/dns-query", "/dns-query{?dns}"},
		{"/resolve", "/resolve{?dns}"},
		// 已带占位符时不应重复追加
		{"/dns-query{?dns}", "/dns-query{?dns}"},
		{"/", "/dns-query{?dns}"},
	}
	for _, tc := range cases {
		if got := ddrDoHPathTemplate(tc.in); got != tc.want {
			t.Fatalf("ddrDoHPathTemplate(%q) = %q，期望 %q", tc.in, got, tc.want)
		}
	}
}

func TestBuildDDRAnswer(t *testing.T) {
	cfg := &EncryptedServerConfig{
		DoTEnabled: true, DoHEnabled: true, DoQEnabled: true,
		DoTPort: 853, DoHPort: 443, DoQPort: 853,
		DoHPath: "/dns-query", ServerName: "dns.lan",
	}

	// 只有 DoH 真的绑上了：其余两项配置开着但没在监听
	answer := BuildDDRAnswer(cfg, "", "0.0.0.0:443", "", []string{"192.168.1.10"})
	if !answer.DoHEnabled {
		t.Fatal("DoH 在监听，应被广播")
	}
	if answer.DoTEnabled || answer.DoQEnabled {
		t.Fatal("未在监听的协议不应被广播")
	}
	if !answer.CertHasIPs {
		t.Fatal("证书含 IP，应标记为真")
	}

	// cfg 为 nil 时返回空内容，不应 panic
	if !BuildDDRAnswer(nil, "", "", "", nil).IsEmpty() {
		t.Fatal("无配置时应为空")
	}
}

func TestDDRCertHasIPs(t *testing.T) {
	if ddrCertHasIPs(nil) || ddrCertHasIPs([]string{"", "  "}) {
		t.Fatal("空列表不应判定为含 IP")
	}
	if !ddrCertHasIPs([]string{"dns.lan", "192.168.1.10"}) {
		t.Fatal("混有 IP 时应判定为含 IP")
	}
	if ddrCertHasIPs([]string{"dns.lan", "not-an-ip"}) {
		t.Fatal("非法串不应判定为含 IP")
	}
	if !ddrCertHasIPs([]string{"::1"}) {
		t.Fatal("IPv6 字面量应被识别")
	}
}

// 中间件在关闭或没有在听的口时必须放行给 SUDN，而不是自行给出空应答
func TestDDRMiddleware_Delegates(t *testing.T) {
	nextCalled := false
	next := func() error {
		nextCalled = true
		return nil
	}

	// 开关关闭
	mw := NewDDRMiddleware(func() bool { return false }, func() DDRAnswer { return fullDDRAnswer() })
	ctx := NewDNSContext(nil, ddrQuery(dns.TypeSVCB), nil, "udp")
	if err := mw(ctx, next); err != nil {
		t.Fatalf("不应报错: %v", err)
	}
	if !nextCalled || ctx.Resp != nil {
		t.Fatal("开关关闭时应原样交给下一个中间件")
	}

	// 开关打开但没有任何在听的协议
	nextCalled = false
	mw = NewDDRMiddleware(func() bool { return true }, func() DDRAnswer { return DDRAnswer{} })
	ctx = NewDNSContext(nil, ddrQuery(dns.TypeSVCB), nil, "udp")
	if err := mw(ctx, next); err != nil {
		t.Fatalf("不应报错: %v", err)
	}
	if !nextCalled || ctx.Resp != nil {
		t.Fatal("无在听协议时应交给 SUDN 处理")
	}

	// 开关打开且有在听的口：就地应答
	nextCalled = false
	mw = NewDDRMiddleware(func() bool { return true }, func() DDRAnswer { return fullDDRAnswer() })
	ctx = NewDNSContext(nil, ddrQuery(dns.TypeSVCB), nil, "udp")
	if err := mw(ctx, next); err != nil {
		t.Fatalf("不应报错: %v", err)
	}
	if nextCalled {
		t.Fatal("命中 DDR 时不应再往下走")
	}
	if ctx.Resp == nil || len(ctx.Resp.Answer) != 3 {
		t.Fatalf("应就地给出三条 SVCB，实得 %v", ctx.Resp)
	}
	if v, _ := ctx.Get("source"); v != "ddr" {
		t.Fatalf("应标记来源为 ddr，实得 %v", v)
	}
}

// 其它名字即使在开关打开时也要放行
func TestDDRMiddleware_IgnoresOtherNames(t *testing.T) {
	nextCalled := false
	next := func() error {
		nextCalled = true
		return nil
	}
	mw := NewDDRMiddleware(func() bool { return true }, func() DDRAnswer { return fullDDRAnswer() })

	m := new(dns.Msg)
	m.SetQuestion("example.com.", dns.TypeSVCB)
	ctx := NewDNSContext(nil, m, nil, "udp")
	if err := mw(ctx, next); err != nil {
		t.Fatalf("不应报错: %v", err)
	}
	if !nextCalled || ctx.Resp != nil {
		t.Fatal("非探测名应原样放行")
	}
}
