package core

import (
	"net"
	"testing"

	"github.com/miekg/dns"
)

// recordEngine 构建一个仅含给定重写规则的重写引擎
func recordEngine(t *testing.T, rules ...RewriteRule) *RewriteEngine {
	t.Helper()
	return NewRewriteEngine(RewriteConfig{Enabled: true, TTL: 60, Rules: rules})
}

func TestRewriteRecords_MXAndSRV(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{
			Domain:  "mail.lan",
			Records: []RewriteRecord{{Type: "MX", Value: "32 example.mail"}},
		},
		RewriteRule{
			Domain:  "_sip._tcp.lan",
			Records: []RewriteRecord{{Type: "SRV", Value: "10 60 8080 sip.lan"}},
		},
	)

	answers, matched := engine.Lookup("mail.lan", dns.TypeMX)
	if !matched || len(answers) != 1 {
		t.Fatalf("MX 查询得到 %d 条记录, matched=%v", len(answers), matched)
	}
	mx, ok := answers[0].(*dns.MX)
	if !ok {
		t.Fatalf("记录类型 = %T, want *dns.MX", answers[0])
	}
	if mx.Preference != 32 || mx.Mx != "example.mail." {
		t.Fatalf("unexpected MX: %+v", mx)
	}

	answers, matched = engine.Lookup("_sip._tcp.lan", dns.TypeSRV)
	if !matched || len(answers) != 1 {
		t.Fatalf("SRV 查询得到 %d 条记录, matched=%v", len(answers), matched)
	}
	srv, ok := answers[0].(*dns.SRV)
	if !ok {
		t.Fatalf("记录类型 = %T, want *dns.SRV", answers[0])
	}
	if srv.Priority != 10 || srv.Weight != 60 || srv.Port != 8080 || srv.Target != "sip.lan." {
		t.Fatalf("unexpected SRV: %+v", srv)
	}

	// MX 查询不应拿到 SRV 记录，反之亦然
	if answers, matched := engine.Lookup("mail.lan", dns.TypeSRV); !matched || len(answers) != 0 {
		t.Fatalf("MX 规则不应影响 SRV 查询: %d 条记录", len(answers))
	}
}

func TestRewriteRecords_NSAndPTR(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{
			Domain:  "delegated.lan",
			Records: []RewriteRecord{{Type: "NS", Value: "ns1.delegated.lan"}},
		},
	)

	answers, matched := engine.Lookup("delegated.lan", dns.TypeNS)
	if !matched || len(answers) != 1 {
		t.Fatalf("NS 查询得到 %d 条记录", len(answers))
	}
	ns, ok := answers[0].(*dns.NS)
	if !ok || ns.Ns != "ns1.delegated.lan." {
		t.Fatalf("unexpected NS: %v", answers[0])
	}
}

func TestRewriteRecords_HTTPSWithParams(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{
			Domain:  "svc.lan",
			Records: []RewriteRecord{{Type: "HTTPS", Value: "1 . alpn=h3,h2 port=8443 ipv4hint=10.0.0.9"}},
		},
	)

	answers, matched := engine.Lookup("svc.lan", dns.TypeHTTPS)
	if !matched || len(answers) != 1 {
		t.Fatalf("HTTPS 查询得到 %d 条记录", len(answers))
	}
	https, ok := answers[0].(*dns.HTTPS)
	if !ok {
		t.Fatalf("记录类型 = %T, want *dns.HTTPS", answers[0])
	}
	if https.Priority != 1 || https.Target != "." {
		t.Fatalf("unexpected HTTPS header: %+v", https.SVCB)
	}

	params := map[dns.SVCBKey]dns.SVCBKeyValue{}
	for _, kv := range https.Value {
		params[kv.Key()] = kv
	}
	alpn, ok := params[dns.SVCB_ALPN].(*dns.SVCBAlpn)
	if !ok || len(alpn.Alpn) != 2 || alpn.Alpn[0] != "h3" {
		t.Fatalf("unexpected alpn: %v", params[dns.SVCB_ALPN])
	}
	if port, ok := params[dns.SVCB_PORT].(*dns.SVCBPort); !ok || port.Port != 8443 {
		t.Fatalf("unexpected port: %v", params[dns.SVCB_PORT])
	}
	hints, ok := params[dns.SVCB_IPV4HINT].(*dns.SVCBIPv4Hint)
	if !ok || len(hints.Hint) != 1 || !hints.Hint[0].Equal(net.ParseIP("10.0.0.9")) {
		t.Fatalf("unexpected ipv4hint: %v", params[dns.SVCB_IPV4HINT])
	}
}

func TestRewriteRecords_RCodeOverridesAnswer(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{Domain: "gone.lan", RCode: "NXDOMAIN"},
		RewriteRule{Domain: "deny.lan", RCode: "REFUSED", IPs: []string{"10.0.0.1"}},
	)

	answers, rcode, matched := engine.LookupDetailed("gone.lan", dns.TypeA)
	if !matched || rcode != dns.RcodeNameError {
		t.Fatalf("rcode = %d, matched = %v", rcode, matched)
	}
	if len(answers) != 0 {
		t.Fatal("非 NOERROR 的重写不应产出记录")
	}

	// 即便同时配了 IP，应答码覆盖也优先：客户端只应看到失败结论
	answers, rcode, matched = engine.LookupDetailed("deny.lan", dns.TypeA)
	if !matched || rcode != dns.RcodeRefused || len(answers) != 0 {
		t.Fatalf("REFUSED 覆盖失败: rcode=%d, %d 条记录", rcode, len(answers))
	}
}

func TestRewriteRecords_UnknownRCodeFallsBack(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{Domain: "typo.lan", RCode: "NOTARCODE", IPs: []string{"10.0.0.1"}},
	)

	// 写错应答码时整条规则仍生效，只是按 NOERROR 处理
	answers, rcode, matched := engine.LookupDetailed("typo.lan", dns.TypeA)
	if !matched || rcode != dns.RcodeSuccess {
		t.Fatalf("rcode = %d, matched = %v", rcode, matched)
	}
	if len(answers) != 1 {
		t.Fatalf("expected the IP record to survive, got %d", len(answers))
	}
}

func TestRewriteRecords_InvalidValuesDropped(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{
			Domain: "mixed.lan",
			Records: []RewriteRecord{
				{Type: "MX", Value: "not-a-preference example.mail"},
				{Type: "SRV", Value: "10 60 8080"},                     // 字段不足
				{Type: "A", Value: "10.0.0.1"},                         // 合法
				{Type: "BOGUS", Value: "whatever"},                     // 类型不受支持
				{Type: "HTTPS", Value: "1 . ipv4hint=1.2.3.4,5.6.7.8"}, // 取值列表被拒
			},
		},
	)

	answers, matched := engine.Lookup("mixed.lan", dns.TypeA)
	if !matched || len(answers) != 1 {
		t.Fatalf("仅合法的 A 记录应保留，得到 %d 条", len(answers))
	}
	if a, ok := answers[0].(*dns.A); !ok || !a.A.Equal(net.ParseIP("10.0.0.1")) {
		t.Fatalf("unexpected record: %v", answers[0])
	}
}

// 快捷字段与显式记录并存时两者都返回
func TestRewriteRecords_CoexistWithShortcutFields(t *testing.T) {
	engine := recordEngine(t,
		RewriteRule{
			Domain:  "both.lan",
			IPs:     []string{"10.0.0.1"},
			Records: []RewriteRecord{{Type: "TXT", Value: "v=spf1 ~all"}},
		},
	)

	if answers, matched := engine.Lookup("both.lan", dns.TypeA); !matched || len(answers) != 1 {
		t.Fatalf("快捷 A 记录丢失: %d 条", len(answers))
	}
	if answers, matched := engine.Lookup("both.lan", dns.TypeTXT); !matched || len(answers) != 1 {
		t.Fatalf("显式 TXT 记录丢失: %d 条", len(answers))
	}
}

func TestParseSVCBParams(t *testing.T) {
	params, err := ParseSVCBParams([]string{"alpn=h2,h3", "no-default-alpn", "dohpath=/dns-query{?dns}"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(params) != 3 {
		t.Fatalf("参数数量 = %d, want 3", len(params))
	}

	for _, tc := range []struct {
		name   string
		params []string
	}{
		{"重复参数", []string{"alpn=h2", "alpn=h3"}},
		{"未知参数", []string{"bogus=1"}},
		{"取值列表", []string{"ipv4hint=1.2.3.4,5.6.7.8"}},
		{"非法端口", []string{"port=99999"}},
		{"缺失取值", []string{"alpn="}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := ParseSVCBParams(tc.params); err == nil {
				t.Fatalf("非法参数应被拒绝: %v", tc.params)
			}
		})
	}
}

func TestRewriteRecordTypes_SortedAndComplete(t *testing.T) {
	types := RewriteRecordTypes()
	if len(types) != len(rewriteRecordTypes) {
		t.Fatalf("类型数量 = %d, want %d", len(types), len(rewriteRecordTypes))
	}
	for i := 1; i < len(types); i++ {
		if types[i-1] > types[i] {
			t.Fatalf("类型列表未排序: %v", types)
		}
	}
}

// $dnsrewrite 修饰符与自定义重写规则共用同一套记录构造，语法应完全一致
func TestRewriteModifier_ExtendedRecordTypes(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||mx.test^$dnsrewrite=NOERROR;MX;32 example.mail",
		"||https.test^$dnsrewrite=NOERROR;HTTPS;1 . alpn=h3",
	)

	res := m.Match("mx.test", dns.TypeMX)
	if !res.IsRewrite() || len(res.Rewritten.Records) != 1 {
		t.Fatalf("unexpected MX result: %+v", res)
	}
	mx, ok := res.Rewritten.Records[0].(*dns.MX)
	if !ok || mx.Preference != 32 || mx.Mx != "example.mail." {
		t.Fatalf("unexpected MX record: %v", res.Rewritten.Records[0])
	}

	res = m.Match("https.test", dns.TypeHTTPS)
	if !res.IsRewrite() || len(res.Rewritten.Records) != 1 {
		t.Fatalf("unexpected HTTPS result: %+v", res)
	}
	if _, ok := res.Rewritten.Records[0].(*dns.HTTPS); !ok {
		t.Fatalf("unexpected HTTPS record: %v", res.Rewritten.Records[0])
	}
}

// 非法取值在解析阶段就该被拒绝，而不是留到查询期静默失效
func TestRewriteModifier_RejectsExtendedInvalidValues(t *testing.T) {
	for _, line := range []string{
		"||x.test^$dnsrewrite=NOERROR;MX;32",
		"||x.test^$dnsrewrite=NOERROR;SRV;10 60 8080",
		"||x.test^$dnsrewrite=NOERROR;HTTPS;1 . ipv4hint=1.2.3.4,5.6.7.8",
	} {
		t.Run(line, func(t *testing.T) {
			if _, ok := ParseRuleLine(line, "test"); ok {
				t.Fatalf("非法重写规则不应被接受: %q", line)
			}
		})
	}
}
