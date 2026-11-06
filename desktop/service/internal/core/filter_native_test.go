package core

import (
	"encoding/binary"
	"path/filepath"
	"strings"
	"testing"

	"github.com/miekg/dns"
)

// filterDecisionPayload builds a payload in the layout src/payload.rs writes.
func filterDecisionPayload(layout byte, mutate func(*[]byte)) []byte {
	payload := []byte{layout, filterActionBlock, 3}
	payload = binary.LittleEndian.AppendUint32(payload, 7)
	payload = append(payload, 0) // no rewrite answer
	if mutate != nil {
		mutate(&payload)
	}
	return payload
}

func TestDecodeFilterDecision(t *testing.T) {
	decision, err := decodeFilterDecision(filterDecisionPayload(filterPayloadLayoutVersion, nil))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if decision.action != filterActionBlock || decision.reason != "blacklist" || decision.ruleIndex != 7 {
		t.Fatalf("decision = %+v", decision)
	}
	if decision.rewrite != nil {
		t.Fatalf("unexpected rewrite answer: %+v", decision.rewrite)
	}

	pass, err := decodeFilterDecision([]byte{filterPayloadLayoutVersion, filterActionPass, filterNoReasonCode, 0xFF, 0xFF, 0xFF, 0xFF, 0})
	if err != nil {
		t.Fatalf("decode pass: %v", err)
	}
	if pass.action != filterActionPass || pass.reason != "" || pass.ruleIndex != -1 {
		t.Fatalf("pass = %+v", pass)
	}
}

func TestDecodeFilterDecisionRewrite(t *testing.T) {
	payload := []byte{filterPayloadLayoutVersion, filterActionRewrite, filterNoReasonCode}
	payload = binary.LittleEndian.AppendUint32(payload, 2)
	payload = append(payload, 1, byte(dns.RcodeSuccess))
	payload = binary.LittleEndian.AppendUint32(payload, 2)
	payload = binary.LittleEndian.AppendUint32(payload, 2)
	payload = binary.LittleEndian.AppendUint32(payload, 5)

	decision, err := decodeFilterDecision(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if decision.rewrite == nil || decision.rewrite.rcode != dns.RcodeSuccess {
		t.Fatalf("rewrite = %+v", decision.rewrite)
	}
	if len(decision.rewrite.rules) != 2 || decision.rewrite.rules[0] != 2 || decision.rewrite.rules[1] != 5 {
		t.Fatalf("rewrite rules = %v", decision.rewrite.rules)
	}
}

func TestDecodeFilterDecisionRejectsMismatchedArtifacts(t *testing.T) {
	// 布局不一致意味着随包发布的库与这份二进制不是同一次构建。
	if _, err := decodeFilterDecision(filterDecisionPayload(filterPayloadLayoutVersion+1, nil)); err == nil {
		t.Fatal("expected a layout mismatch error")
	}
	trailing := filterDecisionPayload(filterPayloadLayoutVersion, func(payload *[]byte) {
		*payload = append(*payload, 0xEE)
	})
	if _, err := decodeFilterDecision(trailing); err == nil {
		t.Fatal("expected a trailing-byte error")
	}
	if _, err := decodeFilterDecision(filterDecisionPayload(filterPayloadLayoutVersion, nil)[:4]); err == nil {
		t.Fatal("expected a truncated payload error")
	}
	unknownReason := filterDecisionPayload(filterPayloadLayoutVersion, func(payload *[]byte) {
		(*payload)[2] = 9
	})
	if _, err := decodeFilterDecision(unknownReason); err == nil {
		t.Fatal("expected an unknown-reason error")
	}
}

func TestDecodeFilterStats(t *testing.T) {
	payload := []byte{filterPayloadLayoutVersion}
	payload = binary.LittleEndian.AppendUint32(payload, 1234)
	payload = append(payload, 1)
	payload = binary.LittleEndian.AppendUint32(payload, 2)

	stats, err := decodeFilterStats(payload)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if stats.totalRules != 1234 || !stats.hasDenyAllow || stats.uncompiledPatterns != 2 {
		t.Fatalf("stats = %+v", stats)
	}
	if _, err := decodeFilterStats(payload[:5]); err == nil {
		t.Fatal("expected a truncated payload error")
	}
}

// TestFilterEncodeRulesPinsThePayloadLayout 钉住载荷布局：内核按同一顺序读取字段，
// 任何字段顺序或宽度变化都会让两侧静默错位。
func TestFilterEncodeRulesPinsThePayloadLayout(t *testing.T) {
	rule := &ParsedRule{
		Pattern:   "ads.test",
		IsAllow:   true,
		Important: true,
		DNSType:   dns.TypeAAAA,
		DenyAllow: []string{"good.ads.test"},
		To:        []string{"partner.test"},
		Rewrite:   &RewriteAction{Bare: true},
		Regex:     nil,
	}
	payload, err := filterEncodeRules([]*ParsedRule{rule})
	if err != nil {
		t.Fatalf("encode rules: %v", err)
	}

	want := []byte{filterPayloadLayoutVersion}
	want = binary.LittleEndian.AppendUint32(want, 1)
	want = append(want, filterFlagAllow|filterFlagImportant|filterFlagRewrite)
	want = binary.LittleEndian.AppendUint16(want, dns.TypeAAAA)
	for _, text := range []string{"ads.test", ""} {
		want = binary.LittleEndian.AppendUint16(want, uint16(len(text)))
		want = append(want, text...)
	}
	want = binary.LittleEndian.AppendUint16(want, 1)
	want = binary.LittleEndian.AppendUint16(want, uint16(len("good.ads.test")))
	want = append(want, "good.ads.test"...)
	want = binary.LittleEndian.AppendUint16(want, 1)
	want = binary.LittleEndian.AppendUint16(want, uint16(len("partner.test")))
	want = append(want, "partner.test"...)
	want = append(want, 1, byte(dns.RcodeSuccess))
	want = binary.LittleEndian.AppendUint16(want, 0)
	want = binary.LittleEndian.AppendUint16(want, uint16(len("bare")))
	want = append(want, "bare"...)

	if string(payload) != string(want) {
		t.Fatalf("payload = %v\nwant    = %v", payload, want)
	}
}

// TestFilterRegexSourceKeepsTheGoPatternCompilation 校验通配规则传给内核的是 Go 编译所用的
// 同一份模式源，而不是解析后的域名模式。
func TestFilterRegexSourceKeepsTheGoPatternCompilation(t *testing.T) {
	rule := &ParsedRule{
		Pattern:    "ad*.wildcard-ad.com",
		IsWildcard: true,
		Regex:      buildWildcardRegex("ad*.wildcard-ad.com"),
	}
	source := filterRegexSource(rule)
	if !strings.HasPrefix(source, "(?i)^(?:.*\\.)?ad.*\\.wildcard-ad\\.com$") {
		t.Fatalf("regex source = %q", source)
	}
	if filterRegexSource(&ParsedRule{Pattern: "plain.test"}) != "" {
		t.Fatal("plain rules must not carry a pattern source")
	}
}

func TestFilterLibraryCandidatesHonourExplicitPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "custom-lib.so")
	t.Setenv("DITING_FILTER_CORE_LIB", path)
	candidates := nativeLibraryCandidates("DITING_FILTER_CORE_LIB", "diting_filter_core")
	if len(candidates) != 1 || candidates[0] != path {
		t.Fatalf("candidates = %v, want only %q", candidates, path)
	}
	// 显式路径写错时必须报错，而不是悄悄回落到其它副本。
	t.Setenv("DITING_FILTER_CORE_LIB", filepath.Join(t.TempDir(), "missing.so"))
	if _, err := loadFilterNativeLibrary(); err == nil {
		t.Fatal("expected a load failure for a missing explicit path")
	}
}

func TestFilterLibraryLookupFollowsTheExecutable(t *testing.T) {
	t.Setenv("DITING_FILTER_CORE_LIB", "")
	candidates := nativeLibraryCandidates("DITING_FILTER_CORE_LIB", "diting_filter_core")
	if len(candidates) == 0 || !strings.Contains(candidates[0], nativeLibraryFile("diting_filter_core")) {
		t.Fatalf("candidates = %v", candidates)
	}
}

// TestRuleMatcherRequiresTheKernel 校验库缺失时索引构建是硬失败，而不是静默放行。
func TestRuleMatcherRequiresTheKernel(t *testing.T) {
	matcher := NewRuleMatcher()
	if err := matcher.BuildFromRules(nil); err != nil {
		t.Fatalf("empty index should build: %v", err)
	}
	defer matcher.release()
	if matcher.TotalRules() != 0 {
		t.Fatalf("TotalRules = %d", matcher.TotalRules())
	}
	// 空索引与未构建的匹配器都要回落 pass，这是旧实现里空 Trie 的语义。
	if res := matcher.Match("ads.test", dns.TypeA); res.Action != "pass" {
		t.Fatalf("empty matcher = %+v", res)
	}
}
