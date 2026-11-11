package dns

import (
	"context"
	"net"
	"strings"
	"testing"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

type pipelineMockResolver struct {
	answers map[string][]dns.RR
}

func (m *pipelineMockResolver) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	return nil, nil
}

func (m *pipelineMockResolver) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	resp := new(dns.Msg)
	resp.SetReply(req)
	if len(req.Question) > 0 {
		key := req.Question[0].Name
		if rrs, ok := m.answers[key]; ok {
			for _, rr := range rrs {
				if rr.Header().Rrtype == req.Question[0].Qtype {
					resp.Answer = append(resp.Answer, rr)
				}
			}
		}
	}
	return resp, nil
}

func (m *pipelineMockResolver) Configure(cfg core.ResolverConfig) error { return nil }
func (m *pipelineMockResolver) Shutdown() error                         { return nil }

func TestPipeline_FullIntegration(t *testing.T) {
	// 1. 初始化各模块
	res := &pipelineMockResolver{
		answers: map[string][]dns.RR{
			"public.example.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "public.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("93.184.216.34")},
			},
			"rebind.example.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "rebind.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("192.168.1.1")},
			},
			"ipv4only.example.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "ipv4only.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("8.8.8.8")},
			},
			"rebind-ipv4only.example.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "rebind-ipv4only.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("10.0.0.1")},
			},
		},
	}

	ac, err := core.NewAccessControl(core.AccessControlConfig{
		BlockedClients: []string{"192.168.100.99"},
	})
	if err != nil {
		t.Fatalf("failed to init AccessControl: %v", err)
	}

	limiter, err := core.NewRateLimiter(context.Background(), core.RateLimitConfig{
		Enabled:    true,
		Rate:       10.0,
		Burst:      2,
		IPv4Prefix: 32,
		IPv6Prefix: 128,
		ExemptIPs:  []string{"127.0.0.1"},
	})
	if err != nil {
		t.Fatalf("NewRateLimiter: %v", err)
	}
	defer limiter.Close()

	rebindMgr := NewRebindProtectionManager(core.RebindConfig{
		Enabled:        true,
		AllowedDomains: []string{"allowed.local"},
	})

	dns64Synth, err := core.NewDNS64Synthesizer(core.DNS64Config{
		Enabled:  true,
		Prefixes: []string{core.WellKnownDNS64Prefix},
	})
	if err != nil {
		t.Fatalf("failed to init DNS64: %v", err)
	}

	edeMw := NewEDEMiddleware(true)
	accessMw := NewAccessMiddleware(ac)
	rateLimitMw := NewRateLimitMiddleware(limiter)
	unqualifiedMw := NewUnqualifiedMiddleware(true)
	rebindMw := NewRebindMiddleware(rebindMgr, nil)
	dns64Mw := NewDNS64Middleware(dns64Synth, res)
	forwardMw := NewForwardMiddleware(res)

	pipeline := NewPipeline(edeMw, accessMw, rateLimitMw, unqualifiedMw, rebindMw, dns64Mw, forwardMw)

	// Case 1: 客户端访问控制阻断 + RFC 8914 EDE 验证
	req1 := new(dns.Msg)
	req1.SetQuestion("public.example.com.", dns.TypeA)
	req1.SetEdns0(4096, false)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("192.168.100.99"), Port: 1234}, "udp")

	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("pipeline execution error: %v", err)
	}
	if ctx1.Resp == nil || ctx1.Resp.Rcode != dns.RcodeRefused {
		t.Fatalf("expected REFUSED for blocked client, got %v", ctx1.Resp)
	}
	ede1 := GetEdns0Option[*dns.EDNS0_EDE](ctx1.Resp)
	if ede1 == nil || ede1.InfoCode != dns.ExtendedErrorCodeProhibited {
		t.Fatalf("expected EDE Prohibited (code 18), got %v", ede1)
	}

	// Case 2: 单标签不完整域名外泄阻断 + EDE 验证
	req2 := new(dns.Msg)
	req2.SetQuestion("printer.", dns.TypeA)
	req2.SetEdns0(4096, false)
	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("192.168.1.50"), Port: 1234}, "udp")

	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("pipeline execution error: %v", err)
	}
	if ctx2.Resp == nil || ctx2.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("expected NXDOMAIN for unqualified query, got %v", ctx2.Resp)
	}
	ede2 := GetEdns0Option[*dns.EDNS0_EDE](ctx2.Resp)
	if ede2 == nil || ede2.InfoCode != dns.ExtendedErrorCodeBlocked {
		t.Fatalf("expected EDE Blocked (code 15), got %v", ede2)
	}

	// Case 3: DNS64 正常合成 AAAA 记录
	req3 := new(dns.Msg)
	req3.SetQuestion("ipv4only.example.com.", dns.TypeAAAA)
	ctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 1234}, "udp")

	if err := pipeline.Execute(ctx3); err != nil {
		t.Fatalf("pipeline execution error: %v", err)
	}
	if ctx3.Resp == nil || len(ctx3.Resp.Answer) != 1 {
		t.Fatalf("expected 1 synthesized AAAA record, got %d", len(ctx3.Resp.Answer))
	}
	aaaa3, ok := ctx3.Resp.Answer[0].(*dns.AAAA)
	if !ok || aaaa3.AAAA.String() != "64:ff9b::808:808" {
		t.Fatalf("expected 64:ff9b::808:808, got %v", aaaa3)
	}

	// Case 4: DNS Rebinding 防御拦截 DNS64 合成的内网私有地址
	req4 := new(dns.Msg)
	req4.SetQuestion("rebind-ipv4only.example.com.", dns.TypeAAAA)
	req4.SetEdns0(4096, false)
	ctx4 := NewDNSContext(context.Background(), req4, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 1234}, "udp")

	if err := pipeline.Execute(ctx4); err != nil {
		t.Fatalf("pipeline execution error: %v", err)
	}
	if ctx4.Resp == nil || len(ctx4.Resp.Answer) != 0 {
		t.Fatalf("expected rebind protection to strip private IP, got %v", ctx4.Resp)
	}
	if val, ok := ctx4.Get("rebinding_blocked"); !ok || val != true {
		t.Fatalf("expected rebinding_blocked attribute to be set")
	}
	ede4 := GetEdns0Option[*dns.EDNS0_EDE](ctx4.Resp)
	if ede4 == nil || ede4.InfoCode != dns.ExtendedErrorCodeProhibited {
		t.Fatalf("expected EDE Prohibited for rebinding attempt, got %v", ede4)
	}

	// Case 5: 速率限制限流测试
	clientIP := net.ParseIP("192.168.1.222")
	for i := 0; i < 2; i++ {
		req := new(dns.Msg)
		req.SetQuestion("public.example.com.", dns.TypeA)
		ctx := NewDNSContext(context.Background(), req, &net.UDPAddr{IP: clientIP, Port: 1234}, "udp")
		_ = pipeline.Execute(ctx)
		if ctx.Resp.Rcode != dns.RcodeSuccess {
			t.Fatalf("query within burst should succeed")
		}
	}
	// 超额请求触发限流
	reqBurst := new(dns.Msg)
	reqBurst.SetQuestion("public.example.com.", dns.TypeA)
	reqBurst.SetEdns0(4096, false)
	ctxBurst := NewDNSContext(context.Background(), reqBurst, &net.UDPAddr{IP: clientIP, Port: 1234}, "udp")
	_ = pipeline.Execute(ctxBurst)
	if ctxBurst.Resp == nil || ctxBurst.Resp.Rcode != dns.RcodeRefused {
		t.Fatalf("expected rate-limited query to return REFUSED")
	}
	edeBurst := GetEdns0Option[*dns.EDNS0_EDE](ctxBurst.Resp)
	if edeBurst == nil || edeBurst.InfoCode != dns.ExtendedErrorCodeProhibited {
		t.Fatalf("expected EDE Prohibited for rate limit")
	}
}

func TestPipeline_RewriteClientAndECSIntegration(t *testing.T) {
	mockRes := &pipelineMockResolver{
		answers: map[string][]dns.RR{
			"upstream.example.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "upstream.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("1.1.1.1")},
			},
		},
	}

	rewriteEngine := newCoreRewriteEngine(t, core.RewriteConfig{
		Enabled: true,
		Rules: []core.RewriteRule{
			{Domain: "*.corp.lan", IPs: []string{"10.10.10.10"}},
		},
	})
	clientResolver := core.NewClientResolver(core.ClientConfig{
		Enabled: true,
		Aliases: []core.ClientAlias{
			{IP: "192.168.1.77", Name: "Office-Printer"},
		},
	}, rewriteEngine)
	ecsMgr := NewECSManager(core.ECSConfig{
		Enabled:  true,
		StripECS: true,
	})

	clientMw := NewClientMiddleware(clientResolver)
	rewriteMw := NewRewriteMiddleware(rewriteEngine)
	ecsMw := NewECSMiddleware(ecsMgr)
	forwardMw := NewForwardMiddleware(mockRes)

	pipeline := NewPipeline(clientMw, rewriteMw, ecsMw, forwardMw)

	// Case 1: 客户端识别与重写命中
	req1 := new(dns.Msg)
	req1.SetQuestion("portal.corp.lan.", dns.TypeA)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("192.168.1.77"), Port: 34567}, "udp")

	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("pipeline error: %v", err)
	}
	if ctx1.ClientName != "Office-Printer" {
		t.Fatalf("expected ClientName Office-Printer, got %s", ctx1.ClientName)
	}
	if ctx1.Resp == nil || len(ctx1.Resp.Answer) != 1 {
		t.Fatalf("expected rewrite answer, got %v", ctx1.Resp)
	}
	aRec := ctx1.Resp.Answer[0].(*dns.A)
	if !aRec.A.Equal(net.ParseIP("10.10.10.10")) {
		t.Fatalf("rewrite IP mismatch: %v", aRec.A)
	}

	// Case 2: 上游转发请求时自动剥离 ECS 隐私子网
	req2 := new(dns.Msg)
	req2.SetQuestion("upstream.example.com.", dns.TypeA)
	_ = SetECS(req2, "192.0.2.0/24")

	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 34567}, "udp")
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("pipeline error: %v", err)
	}
	if ctx2.ClientName != "localhost" {
		t.Fatalf("expected loopback to be localhost, got %s", ctx2.ClientName)
	}
	// 验证请求报文上的 ECS 已被顺利剥离
	if opt := GetEdns0Option[*dns.EDNS0_SUBNET](req2); opt != nil {
		t.Fatalf("expected ECS option to be stripped before upstream forwarding")
	}
}

func TestPipeline_PrivacyAndProtocolEnhancements(t *testing.T) {
	mockRes := &pipelineMockResolver{
		answers: map[string][]dns.RR{
			"secure.example.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "secure.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("1.2.3.4")},
				&dns.HTTPS{
					SVCB: dns.SVCB{
						Hdr:      dns.RR_Header{Name: "secure.example.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
						Priority: 1,
						Target:   ".",
						Value: []dns.SVCBKeyValue{
							&dns.SVCBAlpn{Alpn: []string{"h2", "h3"}},
							&dns.SVCBECHConfig{ECH: []byte{0xaa, 0xbb, 0xcc}},
						},
					},
				},
			},
		},
	}

	blockIPv6 := true
	blockPrivatePTR := true
	blockECH := true

	echMw := NewECHMiddleware(func() bool { return blockECH })
	ipv6Mw := NewIPv6Middleware(func() bool { return blockIPv6 })
	privatePTRMw := NewPrivatePTRMiddleware(func() bool { return blockPrivatePTR }, nil)
	forwardMw := NewForwardMiddleware(mockRes)

	pipeline := NewPipeline(echMw, ipv6Mw, privatePTRMw, forwardMw)

	// 1. 测试 IPv6 AAAA 阻断拦截：返回 NODATA 空应答
	req1 := new(dns.Msg)
	req1.SetQuestion("secure.example.com.", dns.TypeAAAA)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx1.Resp == nil || ctx1.Resp.Rcode != dns.RcodeSuccess || len(ctx1.Resp.Answer) != 0 {
		t.Fatalf("expected NODATA for AAAA query when blockIPv6 is enabled, got %v", ctx1.Resp)
	}
	if src, _ := ctx1.Get("source"); src != "block_ipv6" {
		t.Fatalf("expected source=block_ipv6, got %v", src)
	}

	// 2. 测试 RFC 6303 私有 PTR 防泄漏：权威 NXDOMAIN，防止内网拓扑泄露给上游
	req2 := new(dns.Msg)
	req2.SetQuestion("10.1.168.192.in-addr.arpa.", dns.TypePTR)
	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx2.Resp == nil || ctx2.Resp.Rcode != dns.RcodeNameError {
		t.Fatalf("expected NXDOMAIN for private PTR, got %v", ctx2.Resp)
	}
	if src, _ := ctx2.Get("source"); src != "locally_served_zone" {
		t.Fatalf("expected source=locally_served_zone, got %v", src)
	}

	// 3. 测试 ECH 剥离：上游返回包含 ECH 的 HTTPS 记录，中间件自动剥离 ECH 参数并保留 ALPN
	req3 := new(dns.Msg)
	req3.SetQuestion("secure.example.com.", dns.TypeHTTPS)
	ctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx3); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx3.Resp == nil || len(ctx3.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %v", ctx3.Resp)
	}
	httpsRR, ok := ctx3.Resp.Answer[0].(*dns.HTTPS)
	if !ok {
		t.Fatalf("expected HTTPS record, got %T", ctx3.Resp.Answer[0])
	}
	for _, kv := range httpsRR.Value {
		if kv.Key() == dns.SVCB_ECHCONFIG {
			t.Fatal("expected ECH parameter to be stripped by echMw")
		}
	}
	if stripped, _ := ctx3.Get("ech_stripped"); stripped != true {
		t.Fatal("expected ech_stripped=true")
	}
}

func TestPipeline_HostsRewriteWithIPv6Block(t *testing.T) {
	// 验证流水线正确编排：Hosts 与 Rewrite 优先于 BlockIPv6 权威返回内网已知 IPv6 记录，未匹配的外网上游查询才被 BlockIPv6 拦截 NODATA
	hr, _ := core.NewHostsResolver(core.HostsConfig{Enabled: true})
	hr.LoadReader(strings.NewReader("::1 mylocal.lan\n"))

	re := newCoreRewriteEngine(t, core.RewriteConfig{
		Enabled: true,
		Rules: []core.RewriteRule{
			{Domain: "rewrite.lan", IPs: []string{"2001:db8::99"}},
		},
	})

	mockRes := &pipelineMockResolver{
		answers: map[string][]dns.RR{
			"external.com.": {
				&dns.A{Hdr: dns.RR_Header{Name: "external.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 300}, A: net.ParseIP("93.184.216.34")},
				&dns.HTTPS{
					SVCB: dns.SVCB{
						Hdr:      dns.RR_Header{Name: "external.com.", Rrtype: dns.TypeHTTPS, Class: dns.ClassINET, Ttl: 300},
						Priority: 1,
						Target:   ".",
						Value: []dns.SVCBKeyValue{
							&dns.SVCBAlpn{Alpn: []string{"h2"}},
							&dns.SVCBIPv4Hint{Hint: []net.IP{net.ParseIP("93.184.216.34")}},
							&dns.SVCBIPv6Hint{Hint: []net.IP{net.ParseIP("2606:2800:220:1:248:1893:25c8:1946")}},
							&dns.SVCBECHConfig{ECH: []byte{0x01, 0x02}},
						},
					},
				},
			},
		},
	}

	echMw := NewECHMiddleware(func() bool { return true })
	hostsMw := NewHostsMiddleware(hr)
	rewriteMw := NewRewriteMiddleware(re)
	ipv6Mw := NewIPv6Middleware(func() bool { return true })
	forwardMw := NewForwardMiddleware(mockRes)

	// 正确的流水线序列：hostsMw, rewriteMw 先于 ipv6Mw
	pipeline := NewPipeline(echMw, hostsMw, rewriteMw, ipv6Mw, forwardMw)

	// 1. Hosts 中的 IPv6 查询不应被 BlockIPv6 拦截，权威返回 ::1
	req1 := new(dns.Msg)
	req1.SetQuestion("mylocal.lan.", dns.TypeAAAA)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx1.Resp == nil || len(ctx1.Resp.Answer) != 1 {
		t.Fatalf("expected Hosts to answer mylocal.lan AAAA, got %v", ctx1.Resp)
	}
	if aaaa, ok := ctx1.Resp.Answer[0].(*dns.AAAA); !ok || !aaaa.AAAA.Equal(net.ParseIP("::1")) {
		t.Fatalf("expected ::1 from hosts, got %v", ctx1.Resp.Answer[0])
	}

	// 2. Rewrite 中的 IPv6 查询权威返回重写结果
	req2 := new(dns.Msg)
	req2.SetQuestion("rewrite.lan.", dns.TypeAAAA)
	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx2.Resp == nil || len(ctx2.Resp.Answer) != 1 {
		t.Fatalf("expected Rewrite to answer rewrite.lan AAAA, got %v", ctx2.Resp)
	}
	if aaaa, ok := ctx2.Resp.Answer[0].(*dns.AAAA); !ok || !aaaa.AAAA.Equal(net.ParseIP("2001:db8::99")) {
		t.Fatalf("expected 2001:db8::99 from rewrite, got %v", ctx2.Resp.Answer[0])
	}

	// 3. 未被 Hosts/Rewrite 覆盖的外部 AAAA 查询被 BlockIPv6 拦截并返回 NODATA
	req3 := new(dns.Msg)
	req3.SetQuestion("external.com.", dns.TypeAAAA)
	ctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx3); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx3.Resp == nil || ctx3.Resp.Rcode != dns.RcodeSuccess || len(ctx3.Resp.Answer) != 0 {
		t.Fatalf("expected NODATA for external.com AAAA, got %v", ctx3.Resp)
	}

	// 4. 外部 HTTPS 查询：上游响应同时剥离 ECH (echMw) 与 ipv6hint (ipv6Mw)
	req4 := new(dns.Msg)
	req4.SetQuestion("external.com.", dns.TypeHTTPS)
	ctx4 := NewDNSContext(context.Background(), req4, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx4); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx4.Resp == nil || len(ctx4.Resp.Answer) != 1 {
		t.Fatalf("expected HTTPS answer, got %v", ctx4.Resp)
	}
	httpsRR := ctx4.Resp.Answer[0].(*dns.HTTPS)
	for _, kv := range httpsRR.Value {
		if kv.Key() == dns.SVCB_ECHCONFIG {
			t.Fatal("expected ECH to be stripped")
		}
		if kv.Key() == dns.SVCB_IPV6HINT {
			t.Fatal("expected ipv6hint to be stripped by ipv6Mw")
		}
	}
	if strippedECH, _ := ctx4.Get("ech_stripped"); strippedECH != true {
		t.Fatal("expected ech_stripped=true")
	}
	if strippedIPv6, _ := ctx4.Get("ipv6_hints_stripped"); strippedIPv6 != true {
		t.Fatal("expected ipv6_hints_stripped=true")
	}
}

// 本地权威区必须排在 hosts 之前：区是对整个名字空间的显式声明，
// 反序会让系统 hosts 文件中恰好存在的同名条目掩盖区的权威结论，
// 而区里那条 NODATA 正是用户用来阻止内网名字外泄的。
func TestPipeline_ZonePrecedesHosts(t *testing.T) {
	hr, _ := core.NewHostsResolver(core.HostsConfig{Enabled: true})
	hr.LoadReader(strings.NewReader("10.0.0.1 conflict.lan\n10.0.0.2 outside.example\n"))

	ze := core.NewZoneEngine(core.ZoneConfig{
		Enabled: true,
		Zones: []core.ZoneEntry{{
			ID:      "z",
			Origin:  "lan",
			Enabled: true,
			Content: "$ORIGIN lan.\nconflict IN A 192.168.1.5\n",
		}},
	})

	pipeline := NewPipeline(NewZoneMiddleware(ze), NewHostsMiddleware(hr))

	// 1. 两个来源都有该名字时以区为准
	req1 := new(dns.Msg)
	req1.SetQuestion("conflict.lan.", dns.TypeA)
	ctx1 := NewDNSContext(context.Background(), req1, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx1); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx1.Resp == nil || len(ctx1.Resp.Answer) != 1 {
		t.Fatalf("expected 1 answer, got %v", ctx1.Resp)
	}
	a, ok := ctx1.Resp.Answer[0].(*dns.A)
	if !ok || !a.A.Equal(net.ParseIP("192.168.1.5")) {
		t.Fatalf("expected zone answer 192.168.1.5, got %v", ctx1.Resp.Answer[0])
	}
	if src, _ := ctx1.Get("source"); src != "zone" {
		t.Fatalf("expected source=zone, got %v", src)
	}

	// 2. 区顶点之外的名字不受影响，仍由 hosts 应答
	req2 := new(dns.Msg)
	req2.SetQuestion("outside.example.", dns.TypeA)
	ctx2 := NewDNSContext(context.Background(), req2, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx2); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if src, _ := ctx2.Get("source"); src != "hosts" {
		t.Fatalf("expected hosts to answer outside.example, got source=%v", src)
	}

	// 3. 区内的未知名字短路为权威 NODATA，不得落到 hosts 或更下层。
	// hosts 里即便有同名条目也一并被区覆盖 —— 这正是「区对整个名字空间
	// 负责」的代价，配置界面已就此提示。
	req3 := new(dns.Msg)
	req3.SetQuestion("ghost.lan.", dns.TypeA)
	ctx3 := NewDNSContext(context.Background(), req3, &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 5353}, "udp")
	if err := pipeline.Execute(ctx3); err != nil {
		t.Fatalf("pipeline execute error: %v", err)
	}
	if ctx3.Resp == nil || len(ctx3.Resp.Answer) != 0 || ctx3.Resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("expected authoritative NODATA for ghost.lan, got %v", ctx3.Resp)
	}
	if !ctx3.Resp.Authoritative {
		t.Fatal("expected AA flag on zone NODATA")
	}
}
