package core

import (
	"net"
	"testing"

	"github.com/miekg/dns"
)

// buildRewriteMatcher 从规则文本构建匹配器（解析失败的规则会被丢弃）
func buildRewriteMatcher(t *testing.T, lines ...string) *RuleMatcher {
	t.Helper()
	var rules []*ParsedRule
	for _, line := range lines {
		r, ok := ParseRuleLine(line, "test")
		if !ok {
			t.Fatalf("规则未被解析: %q", line)
		}
		rules = append(rules, r)
	}
	m := NewRuleMatcher()
	m.BuildFromRules(rules)
	return m
}

// aValues 取出结果中的 A 记录地址
func aValues(t *testing.T, res CheckHostResult) []string {
	t.Helper()
	if !res.IsRewrite() {
		t.Fatalf("expected a rewrite result, got %+v", res)
	}
	var out []string
	for _, rr := range res.Rewritten.Records {
		a, ok := rr.(*dns.A)
		if !ok {
			t.Fatalf("expected an A record, got %T", rr)
		}
		out = append(out, a.A.String())
	}
	return out
}

func TestRewriteModifier_ParsesAdGuardSyntax(t *testing.T) {
	for _, tc := range []struct {
		line  string
		check func(t *testing.T, a *RewriteAction)
	}{
		{
			line: "||a.test^$dnsrewrite=127.0.0.1",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RCode != dns.RcodeSuccess || a.RRType != dns.TypeA || a.Value != "127.0.0.1" {
					t.Fatalf("unexpected action: %+v", a)
				}
			},
		},
		{
			line: "||aaaa.test^$dnsrewrite=abcd::1234",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RRType != dns.TypeAAAA {
					t.Fatalf("unexpected rrtype: %d", a.RRType)
				}
			},
		},
		{
			line: "||cname.test^$dnsrewrite=example.org",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RRType != dns.TypeCNAME || a.Value != "example.org" {
					t.Fatalf("unexpected action: %+v", a)
				}
			},
		},
		{
			line: "||refused.test^$dnsrewrite=REFUSED",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RCode != dns.RcodeRefused || a.RRType != 0 {
					t.Fatalf("unexpected action: %+v", a)
				}
			},
		},
		{
			line: "||txt.test^$dnsrewrite=NOERROR;TXT;hello-world",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RRType != dns.TypeTXT || a.Value != "hello-world" {
					t.Fatalf("unexpected action: %+v", a)
				}
			},
		},
		{
			line: "||nx.test^$dnsrewrite=NXDOMAIN;;",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RCode != dns.RcodeNameError {
					t.Fatalf("unexpected action: %+v", a)
				}
			},
		},
		{
			line: "||nodata.test^$dnsrewrite=NOERROR;;",
			check: func(t *testing.T, a *RewriteAction) {
				if a.RCode != dns.RcodeSuccess || a.RRType != 0 {
					t.Fatalf("expected explicit NODATA, got %+v", a)
				}
			},
		},
	} {
		t.Run(tc.line, func(t *testing.T) {
			r, ok := ParseRuleLine(tc.line, "test")
			if !ok {
				t.Fatalf("规则未被解析: %q", tc.line)
			}
			if r.Rewrite == nil {
				t.Fatal("Rewrite 未填充")
			}
			tc.check(t, r.Rewrite)
		})
	}
}

func TestRewriteModifier_RejectsInvalidValues(t *testing.T) {
	for _, line := range []string{
		"||a.test^$dnsrewrite=NOERROR;A;not-an-ip",
		"||a.test^$dnsrewrite=NOERROR;AAAA;1.2.3.4.5",
		"||a.test^$dnsrewrite=NOERROR;XX;1.2.3.4",
		"||a.test^$dnsrewrite=NOERROR;A;",
		// 简写形式落到 CNAME 分支，取值含空格不是合法域名
		"||a.test^$dnsrewrite=not a host",
		// 空标签不是合法域名
		"||a.test^$dnsrewrite=NOERROR;CNAME;bad..host",
	} {
		t.Run(line, func(t *testing.T) {
			if _, ok := ParseRuleLine(line, "test"); ok {
				t.Fatalf("非法重写规则不应被接受: %q", line)
			}
		})
	}
}

func TestRewriteModifier_AnswerParsing(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||a.test^$dnsrewrite=127.0.0.1",
		"||aaaa.test^$dnsrewrite=abcd::1234",
		"||txt.test^$dnsrewrite=NOERROR;TXT;hello-world",
		"||refused.test^$dnsrewrite=REFUSED",
	)

	res := m.Match("a.test", dns.TypeA)
	if got := aValues(t, res); len(got) != 1 || got[0] != "127.0.0.1" {
		t.Fatalf("A 记录 = %v, want [127.0.0.1]", got)
	}
	if res.Reason != ReasonDNSRewrite || res.Blocked {
		t.Fatalf("unexpected result: %+v", res)
	}

	res = m.Match("aaaa.test", dns.TypeAAAA)
	if !res.IsRewrite() || len(res.Rewritten.Records) != 1 {
		t.Fatalf("unexpected AAAA result: %+v", res)
	}
	aaaa := res.Rewritten.Records[0].(*dns.AAAA)
	if !aaaa.AAAA.Equal(net.ParseIP("abcd::1234")) {
		t.Fatalf("AAAA = %v", aaaa.AAAA)
	}

	res = m.Match("txt.test", dns.TypeTXT)
	txt := res.Rewritten.Records[0].(*dns.TXT)
	if len(txt.Txt) != 1 || txt.Txt[0] != "hello-world" {
		t.Fatalf("TXT = %v", txt.Txt)
	}

	// 非 NOERROR 应答码：不产出任何记录
	res = m.Match("refused.test", dns.TypeA)
	if !res.IsRewrite() || res.Rewritten.RCode != dns.RcodeRefused || len(res.Rewritten.Records) != 0 {
		t.Fatalf("unexpected REFUSED result: %+v", res)
	}
}

// 查询类型与重写记录类型不一致时得到权威 NODATA，而不是放行到上游
func TestRewriteModifier_NodataForOtherTypes(t *testing.T) {
	m := buildRewriteMatcher(t, "||a.test^$dnsrewrite=127.0.0.1")

	res := m.Match("a.test", dns.TypeAAAA)
	if !res.IsRewrite() {
		t.Fatalf("expected a rewrite hit, got %+v", res)
	}
	if res.Rewritten.RCode != dns.RcodeSuccess || len(res.Rewritten.Records) != 0 {
		t.Fatalf("expected authoritative NODATA, got %+v", res.Rewritten)
	}
}

// 同名多条同类型重写记录求和到同一应答
func TestRewriteModifier_MultipleRecordsSum(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||multi.test^$dnsrewrite=127.0.0.1",
		"||multi.test^$dnsrewrite=127.0.0.2",
	)

	got := aValues(t, m.Match("multi.test", dns.TypeA))
	if len(got) != 2 || got[0] != "127.0.0.1" || got[1] != "127.0.0.2" {
		t.Fatalf("expected both records, got %v", got)
	}
}

// CNAME 对任意查询类型都成立：别名是名字本身的属性
func TestRewriteModifier_CNAMEServedForAnyType(t *testing.T) {
	m := buildRewriteMatcher(t, "||cname.test^$dnsrewrite=new-cname.test")

	for _, qtype := range []uint16{dns.TypeA, dns.TypeAAAA, dns.TypeMX} {
		res := m.Match("cname.test", qtype)
		if !res.IsRewrite() || len(res.Rewritten.Records) != 1 {
			t.Fatalf("qtype %d: unexpected result %+v", qtype, res)
		}
		if _, ok := res.Rewritten.Records[0].(*dns.CNAME); !ok {
			t.Fatalf("qtype %d: expected CNAME, got %T", qtype, res.Rewritten.Records[0])
		}
	}
}

// 带取值的例外规则只取消取值相同的那一条，不影响其它重写
func TestRewriteModifier_ExceptionCancelsOneValue(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||one.test^$dnsrewrite=127.0.0.1",
		"||one.test^$dnsrewrite=127.0.0.2",
		"@@||one.test^$dnsrewrite=127.0.0.1",
	)

	got := aValues(t, m.Match("one.test", dns.TypeA))
	if len(got) != 1 || got[0] != "127.0.0.2" {
		t.Fatalf("expected only 127.0.0.2, got %v", got)
	}
}

// 裸 $dnsrewrite 例外取消该域名的全部重写
func TestRewriteModifier_BareExceptionCancelsAll(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||all.test^$dnsrewrite=127.0.0.1",
		"||all.test^$dnsrewrite=127.0.0.2",
		"@@||all.test^$dnsrewrite",
	)

	res := m.Match("all.test", dns.TypeA)
	if res.IsRewrite() {
		t.Fatalf("expected the rewrite to be cancelled, got %+v", res)
	}
	if res.Action != "pass" {
		t.Fatalf("expected pass, got %+v", res)
	}
}

// 取消重写不能被误当成整域放行：该域名下的黑名单规则必须仍然生效
func TestRewriteModifier_ExceptionDoesNotUnblock(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||mix.test^$dnsrewrite=127.0.0.1",
		"||mix.test^",
		"@@||mix.test^$dnsrewrite",
	)

	res := m.Match("mix.test", dns.TypeA)
	if !res.Blocked {
		t.Fatalf("黑名单规则必须仍然生效，得到 %+v", res)
	}
	if res.Reason != "blacklist" {
		t.Fatalf("expected a blacklist hit, got %+v", res)
	}
}

// 重写优先于一切拦截规则（对齐 AdGuard Home）
func TestRewriteModifier_TakesPrecedenceOverBlock(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||both.test^",
		"||both.test^$dnsrewrite=127.0.0.1",
	)

	res := m.Match("both.test", dns.TypeA)
	if res.Blocked || !res.IsRewrite() {
		t.Fatalf("重写必须优先于黑名单拦截，得到 %+v", res)
	}
}

// 重写与 $important 拦截规则相比同样优先
func TestRewriteModifier_TakesPrecedenceOverImportantBlock(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||imp.test^$important",
		"||imp.test^$dnsrewrite=127.0.0.1",
	)

	res := m.Match("imp.test", dns.TypeA)
	if res.Blocked || !res.IsRewrite() {
		t.Fatalf("重写必须优先于 $important 拦截，得到 %+v", res)
	}
}

// 父域重写规则覆盖子域（对齐字典树的父域继承语义）
func TestRewriteModifier_InheritsToSubdomains(t *testing.T) {
	m := buildRewriteMatcher(t, "||parent.test^$dnsrewrite=127.0.0.1")

	res := m.Match("deep.sub.parent.test", dns.TypeA)
	if got := aValues(t, res); len(got) != 1 || got[0] != "127.0.0.1" {
		t.Fatalf("expected the parent rewrite to apply, got %v", got)
	}
}

// 通配符形式的重写规则
func TestRewriteModifier_WildcardRule(t *testing.T) {
	m := buildRewriteMatcher(t, "||*.wild.test^$dnsrewrite=127.0.0.1")

	res := m.Match("anything.wild.test", dns.TypeA)
	if got := aValues(t, res); len(got) != 1 || got[0] != "127.0.0.1" {
		t.Fatalf("expected the wildcard rewrite to apply, got %v", got)
	}
}

// 非 NOERROR 应答码优先于记录：明确的失败应答比伪造成功应答更安全
func TestRewriteModifier_FailureCodeWinsOverRecords(t *testing.T) {
	m := buildRewriteMatcher(t,
		"||fail.test^$dnsrewrite=127.0.0.1",
		"||fail.test^$dnsrewrite=SERVFAIL",
	)

	res := m.Match("fail.test", dns.TypeA)
	if !res.IsRewrite() || res.Rewritten.RCode != dns.RcodeServerFailure {
		t.Fatalf("expected SERVFAIL to win, got %+v", res)
	}
	if len(res.Rewritten.Records) != 0 {
		t.Fatal("失败应答不应携带记录")
	}
}

// 重写命中应被标记为独立动作，不计入拦截/放行统计
func TestRewriteModifier_NotCountedAsBlockOrAllow(t *testing.T) {
	engine := NewRuleEngine(FilterConfig{
		Enabled:      true,
		BlockMode:    BlockModeNullIP,
		DataDir:      t.TempDir(),
		CustomRules:  []string{"||stats.test^$dnsrewrite=127.0.0.1"},
		Lists:        []FilterList{},
		BlockingIPv4: DefaultBlockingIPv4,
		BlockingIPv6: DefaultBlockingIPv6,
	})
	defer engine.Close()

	res := engine.Match("stats.test", dns.TypeA)
	if !res.IsRewrite() {
		t.Fatalf("expected a rewrite hit, got %+v", res)
	}

	stats := engine.GetStats()
	if stats.BlockedQueries != 0 || stats.AllowedQueries != 0 {
		t.Fatalf("重写不应计入拦截或放行统计: %+v", stats)
	}
}

func TestRewriteAction_String(t *testing.T) {
	for _, tc := range []struct {
		in   *RewriteAction
		want string
	}{
		{&RewriteAction{Bare: true}, "$dnsrewrite"},
		{&RewriteAction{RCode: dns.RcodeRefused}, "REFUSED"},
		{&RewriteAction{RCode: dns.RcodeSuccess}, "NOERROR;;"},
		{&RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeA, Value: "1.2.3.4"}, "A 1.2.3.4"},
	} {
		if got := tc.in.String(); got != tc.want {
			t.Fatalf("String() = %q, want %q", got, tc.want)
		}
	}
}
