package core

// parse_native_test.go 钉住解析器边界：请求/回应的载荷布局、标志位、失败路径，以及
// 「内核解析完、Go 仍要补做的那几步」（正则编译、$dnsrewrite 取值解析）。

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"

	"github.com/miekg/dns"
)

// TestParseEncodeRequestPinsThePayloadLayout 钉住请求布局：内核按同一顺序读取字段。
func TestParseEncodeRequestPinsThePayloadLayout(t *testing.T) {
	payload := parseEncodeRequest("a.test")

	want := []byte{parseNativeLayoutVersion}
	want = binary.LittleEndian.AppendUint32(want, uint32(len("a.test")))
	want = append(want, "a.test"...)
	if string(payload) != string(want) {
		t.Fatalf("payload = %v\nwant    = %v", payload, want)
	}
}

// parsedLinePayload 构造内核写出的单条规则记录（原始行、模式、标志位、类型、两个集合、重写取值）。
func parsedLinePayload(flags uint8, rewrite *string) []byte {
	payload := []byte{parseNativeLayoutVersion}
	payload = binary.LittleEndian.AppendUint32(payload, 1)
	for _, text := range []string{"||ads.test^", "ads.test"} {
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(text)))
		payload = append(payload, text...)
	}
	payload = append(payload, flags)
	payload = binary.LittleEndian.AppendUint16(payload, dns.TypeAAAA)
	payload = binary.LittleEndian.AppendUint16(payload, 0) // denyallow 条数
	payload = binary.LittleEndian.AppendUint16(payload, 0) // to 条数
	if rewrite != nil {
		payload = binary.LittleEndian.AppendUint32(payload, uint32(len(*rewrite)))
		payload = append(payload, *rewrite...)
	}
	return payload
}

func TestDecodeParsedLines(t *testing.T) {
	value := "NOERROR;TXT;hi"
	lines, err := decodeParsedLines(parsedLinePayload(filterFlagAllow|filterFlagRewrite, &value))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(lines) != 1 {
		t.Fatalf("lines = %d", len(lines))
	}
	line := lines[0]
	if line.raw != "||ads.test^" || line.pattern != "ads.test" {
		t.Fatalf("line = %+v", line)
	}
	if line.flags != filterFlagAllow|filterFlagRewrite || line.dnsType != dns.TypeAAAA {
		t.Fatalf("line = %+v", line)
	}
	if line.rewrite == nil || *line.rewrite != value {
		t.Fatalf("rewrite = %v", line.rewrite)
	}
	if len(line.denyAllow) != 0 || len(line.to) != 0 {
		t.Fatalf("line = %+v", line)
	}
}

func TestDecodeParsedLinesRejectsMismatchedArtifacts(t *testing.T) {
	// 布局或标志位不符意味着随包发布的库与这份二进制不是同一次构建。
	mismatched := parsedLinePayload(0, nil)
	mismatched[0]++
	if _, err := decodeParsedLines(mismatched); err == nil {
		t.Fatal("expected a layout mismatch error")
	}

	unknownFlags := parsedLinePayload(1<<6, nil)
	if _, err := decodeParsedLines(unknownFlags); err == nil {
		t.Fatal("expected an unknown-flags error")
	}

	trailing := append(parsedLinePayload(0, nil), 0xEE)
	if _, err := decodeParsedLines(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}

	if _, err := decodeParsedLines(parsedLinePayload(0, nil)[:6]); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

// TestParseRuleLineThroughTheKernel 校验内核结果到 ParsedRule 的映射（含 Go 补做的正则编译）。
func TestParseRuleLineThroughTheKernel(t *testing.T) {
	cases := []struct {
		line       string
		valid      bool
		pattern    string
		isAllow    bool
		important  bool
		isRegex    bool
		isWildcard bool
		isExact    bool
		dnsType    uint16
		denyAllow  []string
		to         []string
	}{
		{line: "||ad.doubleclick.net^", valid: true, pattern: "ad.doubleclick.net"},
		{line: "@@||safe.doubleclick.net^", valid: true, pattern: "safe.doubleclick.net", isAllow: true},
		{line: "||critical.ad.com^$important", valid: true, pattern: "critical.ad.com", important: true},
		{line: "0.0.0.0 hosts-malware.com", valid: true, pattern: "hosts-malware.com"},
		{line: "|exact-domain.com|", valid: true, pattern: "exact-domain.com", isExact: true},
		{line: "||ipv6only.ad.com^$dnstype=AAAA", valid: true, pattern: "ipv6only.ad.com", dnsType: dns.TypeAAAA},
		{line: "/^banner[0-9]+\\.ad\\.com$/", valid: true, pattern: "^banner[0-9]+\\.ad\\.com$", isRegex: true},
		{line: "||ad*.wildcard-ad.com^", valid: true, pattern: "ad*.wildcard-ad.com", isWildcard: true},
		{
			line:      "||tracker.com^$denyallow=ads.com|good.ads.com,to=partner.test",
			valid:     true,
			pattern:   "tracker.com",
			denyAllow: []string{"ads.com", "good.ads.com"},
			to:        []string{"partner.test"},
		},
		{line: "# comment", valid: false},
		{line: "youtube.com##.video-ads", valid: false},
		{line: "||cdn.example.com^$image", valid: false},
		{line: "||x.test^$badfilter", valid: false},
	}

	for _, c := range cases {
		rule, ok := ParseRuleLine(c.line, "test")
		if ok != c.valid {
			t.Fatalf("%q valid = %v, want %v", c.line, ok, c.valid)
		}
		if !ok {
			continue
		}
		if rule.Pattern != c.pattern || rule.IsAllow != c.isAllow || rule.Important != c.important ||
			rule.IsRegex != c.isRegex || rule.IsWildcard != c.isWildcard || rule.IsExact != c.isExact {
			t.Fatalf("%q = %+v", c.line, rule)
		}
		if c.dnsType != 0 && rule.DNSType != c.dnsType {
			t.Fatalf("%q dnstype = %d, want %d", c.line, rule.DNSType, c.dnsType)
		}
		if strings.Join(rule.DenyAllow, ",") != strings.Join(c.denyAllow, ",") ||
			strings.Join(rule.To, ",") != strings.Join(c.to, ",") {
			t.Fatalf("%q exclusions = %v / %v", c.line, rule.DenyAllow, rule.To)
		}
		if rule.Source != "test" || rule.Raw != c.line {
			t.Fatalf("%q raw/source = %q / %q", c.line, rule.Raw, rule.Source)
		}
		if rule.IsRegex && rule.Regex == nil {
			t.Fatalf("%q 缺少编译后的正则", c.line)
		}
		if rule.IsWildcard && rule.Regex == nil {
			t.Fatalf("%q 缺少通配正则", c.line)
		}
	}
}

// TestParseRuleLineDropsWhatGoStillRefuses 校验 Go 侧的两处丢弃：正则编译失败、$dnsrewrite 取值非法。
func TestParseRuleLineDropsWhatGoStillRefuses(t *testing.T) {
	if rule, ok := ParseRuleLine("/(/", "test"); ok || rule != nil {
		t.Fatalf("非法正则不应被保留: %+v", rule)
	}
	if rule, ok := ParseRuleLine("||a.test^$dnsrewrite=NOERROR;NOTATYPE;x", "test"); ok || rule != nil {
		t.Fatalf("非法 $dnsrewrite 取值不应被保留: %+v", rule)
	}

	rule, ok := ParseRuleLine("||a.test^$dnsrewrite=NOERROR;TXT;hello_world", "test")
	if !ok || rule == nil || rule.Rewrite == nil {
		t.Fatalf("合法 $dnsrewrite 应被保留: %+v", rule)
	}
	if rule.Rewrite.RRType != dns.TypeTXT || rule.Rewrite.Value != "hello_world" {
		t.Fatalf("rewrite = %+v", rule.Rewrite)
	}
}

// TestParseRulesDocument 校验整份列表的解析顺序与 hosts 多域名展开。
func TestParseRulesDocument(t *testing.T) {
	content := strings.Join([]string{
		"# header",
		"0.0.0.0 host1.com host2.com  host3.com # comment",
		"||plain.test^",
		"@@||allow.plain.test^",
		"not-a-rule##selector",
	}, "\n") + "\n"

	rules, err := ParseRules(bytes.NewReader([]byte(content)), "list-1")
	if err != nil {
		t.Fatalf("ParseRules: %v", err)
	}
	patterns := make([]string, 0, len(rules))
	for _, rule := range rules {
		patterns = append(patterns, rule.Pattern)
		if rule.Source != "list-1" {
			t.Fatalf("rule source = %q", rule.Source)
		}
	}
	want := []string{"host1.com", "host2.com", "host3.com", "plain.test", "allow.plain.test"}
	if strings.Join(patterns, ",") != strings.Join(want, ",") {
		t.Fatalf("patterns = %v, want %v", patterns, want)
	}
	if rules[4].IsAllow != true {
		t.Fatalf("第 5 条应为白名单规则: %+v", rules[4])
	}
}

// TestParseRulesKeepsNonUTF8Lines 校验非 UTF-8 字节不会让整份列表加载失败。
func TestParseRulesKeepsNonUTF8Lines(t *testing.T) {
	content := append([]byte("||good.test^\n"), 0xFF, 0xFE, '\n')
	content = append(content, []byte("||good2.test^\n")...)

	rules, err := ParseRules(bytes.NewReader(content), "list")
	if err != nil {
		t.Fatalf("ParseRules: %v", err)
	}
	if len(rules) != 2 || rules[0].Pattern != "good.test" || rules[1].Pattern != "good2.test" {
		t.Fatalf("rules = %+v", rules)
	}
}
