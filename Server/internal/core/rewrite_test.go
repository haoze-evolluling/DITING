package core

import (
	"net"
	"testing"

	"github.com/miekg/dns"
)

func TestRewriteEngine_ExactAndWildcard(t *testing.T) {
	cfg := RewriteConfig{
		Enabled: true,
		TTL:     120,
		Rules: []RewriteRule{
			{
				Domain: "nas.lan",
				IPs:    []string{"192.168.1.100", "fe80::1"},
			},
			{
				Domain: "*.test",
				IPs:    []string{"127.0.0.1"},
			},
			{
				Domain: "alias.local",
				CNAME:  "target.example.com",
			},
			{
				Domain: "meta.lan",
				TXT:    []string{"v=spf1 ~all", "status=ok"},
			},
		},
	}

	engine := NewRewriteEngine(cfg)

	// 1. 测试精准匹配 A 记录
	answers, matched := engine.Lookup("nas.lan.", dns.TypeA)
	if !matched || len(answers) != 1 {
		t.Fatalf("expected 1 A record for nas.lan, got %d, matched=%v", len(answers), matched)
	}
	aRecord, ok := answers[0].(*dns.A)
	if !ok || !aRecord.A.Equal(net.ParseIP("192.168.1.100")) {
		t.Fatalf("unexpected A record value: %v", answers[0])
	}
	if aRecord.Hdr.Ttl != 120 {
		t.Fatalf("expected TTL 120, got %d", aRecord.Hdr.Ttl)
	}

	// 2. 测试精准匹配 AAAA 记录
	answers, matched = engine.Lookup("nas.lan", dns.TypeAAAA)
	if !matched || len(answers) != 1 {
		t.Fatalf("expected 1 AAAA record for nas.lan, got %d", len(answers))
	}
	aaaaRecord, ok := answers[0].(*dns.AAAA)
	if !ok || !aaaaRecord.AAAA.Equal(net.ParseIP("fe80::1")) {
		t.Fatalf("unexpected AAAA record value: %v", answers[0])
	}

	// 3. 测试泛域名匹配
	subdomains := []string{"app.test", "api.v1.test", "my-site.test."}
	for _, sub := range subdomains {
		answers, matched = engine.Lookup(sub, dns.TypeA)
		if !matched || len(answers) != 1 {
			t.Fatalf("expected wildcard match for %s, got len=%d matched=%v", sub, len(answers), matched)
		}
		aRec := answers[0].(*dns.A)
		if !aRec.A.Equal(net.ParseIP("127.0.0.1")) {
			t.Fatalf("wildcard IP mismatch: %v", aRec.A)
		}
	}

	// 4. 测试 CNAME 记录重写 (支持 TypeA 和 TypeCNAME 查询)
	answers, matched = engine.Lookup("alias.local", dns.TypeA)
	if !matched || len(answers) != 1 {
		t.Fatalf("expected CNAME for alias.local A query, got %d", len(answers))
	}
	cnameRec, ok := answers[0].(*dns.CNAME)
	if !ok || cnameRec.Target != "target.example.com." {
		t.Fatalf("unexpected CNAME target: %v", answers[0])
	}

	// 5. 测试 TXT 记录重写
	answers, matched = engine.Lookup("meta.lan", dns.TypeTXT)
	if !matched || len(answers) != 1 {
		t.Fatalf("expected TXT record for meta.lan, got %d", len(answers))
	}
	txtRec := answers[0].(*dns.TXT)
	if len(txtRec.Txt) != 2 || txtRec.Txt[0] != "v=spf1 ~all" {
		t.Fatalf("unexpected TXT record values: %v", txtRec.Txt)
	}

	// 6. 测试权威 NODATA (匹配了域名但未匹配查询类型，如 MX)
	answers, matched = engine.Lookup("nas.lan", dns.TypeMX)
	if !matched {
		t.Fatalf("expected matched=true for NODATA detection")
	}
	if len(answers) != 0 {
		t.Fatalf("expected empty answers for NODATA, got %d", len(answers))
	}

	// 7. 测试自动反向 PTR 解析
	ptrQuery, err := dns.ReverseAddr("192.168.1.100")
	if err != nil {
		t.Fatalf("reverseAddr failed: %v", err)
	}
	ptrAns, ptrMatched := engine.LookupPTR(ptrQuery)
	if !ptrMatched || len(ptrAns) != 1 {
		t.Fatalf("expected PTR match for 192.168.1.100, got len=%d matched=%v", len(ptrAns), ptrMatched)
	}
	ptrRecord, ok := ptrAns[0].(*dns.PTR)
	if !ok || ptrRecord.Ptr != "nas.lan." {
		t.Fatalf("unexpected PTR target: %v", ptrAns[0])
	}

	// 8. 测试 IPv4-mapped IPv6 反向反查
	revName := engine.LookupReverse(net.ParseIP("::ffff:192.168.1.100"))
	if revName != "nas.lan" {
		t.Fatalf("expected nas.lan for IPv4-mapped IPv6, got %s", revName)
	}
}

func TestRewriteEngine_CNAMEChainingAndLoops(t *testing.T) {
	cfg := RewriteConfig{
		Enabled: true,
		Rules: []RewriteRule{
			{Domain: "alias1.lan", CNAME: "alias2.lan"},
			{Domain: "alias2.lan", CNAME: "target.lan"},
			{Domain: "target.lan", IPs: []string{"192.168.8.8"}},
			// 循环测试规则
			{Domain: "loop1.lan", CNAME: "loop2.lan"},
			{Domain: "loop2.lan", CNAME: "loop1.lan"},
		},
	}
	engine := NewRewriteEngine(cfg)

	// 1. 测试深度链式解析：alias1.lan -> alias2.lan -> target.lan -> 192.168.8.8
	ans, matched := engine.Lookup("alias1.lan", dns.TypeA)
	if !matched || len(ans) != 3 {
		t.Fatalf("expected 3 answers (2 CNAMEs + 1 A), got len=%d matched=%v", len(ans), matched)
	}
	cname1 := ans[0].(*dns.CNAME)
	cname2 := ans[1].(*dns.CNAME)
	aRec := ans[2].(*dns.A)
	if cname1.Target != "alias2.lan." || cname2.Target != "target.lan." || !aRec.A.Equal(net.ParseIP("192.168.8.8")) {
		t.Fatalf("unexpected chained answers: %v", ans)
	}

	// 2. 测试循环 CNAME 保护：loop1.lan -> loop2.lan -> loop1.lan 不死循环
	loopAns, loopMatched := engine.Lookup("loop1.lan", dns.TypeA)
	if !loopMatched || len(loopAns) < 1 {
		t.Fatalf("expected graceful loop termination, got %v", loopAns)
	}
}

func TestRewriteEngine_WildcardLongestSuffix(t *testing.T) {
	// 无论添加顺序如何，长后缀规则必须优先匹配
	cfg := RewriteConfig{
		Enabled: true,
		Rules: []RewriteRule{
			{Domain: "*.lan", IPs: []string{"10.0.0.1"}},
			{Domain: "*.corp.lan", IPs: []string{"10.0.0.2"}},
			{Domain: "*.deep.sub.corp.lan", IPs: []string{"10.0.0.3"}},
		},
	}
	engine := NewRewriteEngine(cfg)

	ans, _ := engine.Lookup("my.deep.sub.corp.lan", dns.TypeA)
	if len(ans) != 1 || !ans[0].(*dns.A).A.Equal(net.ParseIP("10.0.0.3")) {
		t.Fatalf("expected 10.0.0.3 for deepest wildcard, got %v", ans)
	}

	ans, _ = engine.Lookup("my.corp.lan", dns.TypeA)
	if len(ans) != 1 || !ans[0].(*dns.A).A.Equal(net.ParseIP("10.0.0.2")) {
		t.Fatalf("expected 10.0.0.2 for corp.lan wildcard, got %v", ans)
	}

	ans, _ = engine.Lookup("my.lan", dns.TypeA)
	if len(ans) != 1 || !ans[0].(*dns.A).A.Equal(net.ParseIP("10.0.0.1")) {
		t.Fatalf("expected 10.0.0.1 for .lan wildcard, got %v", ans)
	}
}

func TestRewriteEngine_MultiAliasPTR(t *testing.T) {
	cfg := RewriteConfig{
		Enabled: true,
		Rules: []RewriteRule{
			{Domain: "nas.lan", IPs: []string{"192.168.1.50"}},
			{Domain: "storage.lan", IPs: []string{"192.168.1.50"}},
		},
	}
	engine := NewRewriteEngine(cfg)

	ptrQuery, _ := dns.ReverseAddr("192.168.1.50")
	ans, matched := engine.LookupPTR(ptrQuery)
	if !matched || len(ans) != 2 {
		t.Fatalf("expected 2 PTR records for shared IP, got len=%d matched=%v", len(ans), matched)
	}
}

func TestRewriteEngine_DynamicRules(t *testing.T) {
	engine := NewRewriteEngine(DefaultRewriteConfig())

	// 初始状态无规则
	if _, matched := engine.Lookup("dynamic.dev", dns.TypeA); matched {
		t.Fatalf("should not match initially")
	}

	// 动态添加
	err := engine.AddRule(RewriteRule{
		Domain: "dynamic.dev",
		IPs:    []string{"10.10.10.10"},
	})
	if err != nil {
		t.Fatalf("add rule error: %v", err)
	}

	ans, matched := engine.Lookup("dynamic.dev", dns.TypeA)
	if !matched || len(ans) != 1 {
		t.Fatalf("expected dynamic.dev to match after AddRule")
	}

	// 动态删除
	deleted := engine.DeleteRule("dynamic.dev")
	if !deleted {
		t.Fatalf("expected DeleteRule to return true")
	}

	_, matched = engine.Lookup("dynamic.dev", dns.TypeA)
	if matched {
		t.Fatalf("should not match after DeleteRule")
	}
}

// 同一属主名不得同时返回 CNAME 与其他类型（RFC 1034 §3.6.2）。
func TestRewriteEngine_ShortcutAndRecordsCNAMEExclusive(t *testing.T) {
	cfg := RewriteConfig{
		Enabled: true,
		Rules: []RewriteRule{{
			Domain: "dual.lan",
			Records: []RewriteRecord{
				{Type: "CNAME", Value: "final.lan."},
				{Type: "A", Value: "10.1.2.3"},
			},
		}},
	}
	engine := NewRewriteEngine(cfg)
	ans, matched := engine.Lookup("dual.lan", dns.TypeA)
	if !matched {
		t.Fatal("规则应命中")
	}
	for _, rr := range ans {
		if rr.Header().Rrtype != dns.TypeCNAME {
			t.Fatalf("同属主名不应与 CNAME 并存其他记录: %v", ans)
		}
	}
}

// IPv4 字面量不能被当成 AAAA 接受（To16 对 v4-mapped 恒非 nil）。
func TestRewriteEngine_AAAARejectsIPv4Literal(t *testing.T) {
	cfg := RewriteConfig{
		Enabled: true,
		Rules: []RewriteRule{{
			Domain:  "bad6.lan",
			Records: []RewriteRecord{{Type: "AAAA", Value: "10.0.0.5"}},
		}},
	}
	engine := NewRewriteEngine(cfg)
	if ans, _ := engine.Lookup("bad6.lan", dns.TypeAAAA); len(ans) != 0 {
		t.Fatalf("IPv4 字面量不应被接受为 AAAA: %v", ans)
	}
}
