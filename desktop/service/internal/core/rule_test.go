package core

import (
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func TestRuleParser(t *testing.T) {
	cases := []struct {
		line      string
		valid     bool
		pattern   string
		isAllow   bool
		important bool
		isRegex   bool
		dnsType   uint16
	}{
		{line: "# This is a comment", valid: false},
		{line: "! Adblock comment", valid: false},
		{line: "", valid: false},
		{line: "||ad.doubleclick.net^", valid: true, pattern: "ad.doubleclick.net", isAllow: false},
		{line: "@@||safe.doubleclick.net^", valid: true, pattern: "safe.doubleclick.net", isAllow: true},
		{line: "||critical.ad.com^$important", valid: true, pattern: "critical.ad.com", important: true},
		{line: "0.0.0.0 hosts-malware.com", valid: true, pattern: "hosts-malware.com"},
		{line: "127.0.0.1  tracker.org", valid: true, pattern: "tracker.org"},
		{line: "|exact-domain.com|", valid: true, pattern: "exact-domain.com"},
		{line: "||ipv6only.ad.com^$dnstype=AAAA", valid: true, pattern: "ipv6only.ad.com", dnsType: dns.TypeAAAA},
		{line: "/^banner[0-9]+\\.ad\\.com$/", valid: true, isRegex: true},
	}

	for _, c := range cases {
		rule, ok := ParseRuleLine(c.line, "test")
		if ok != c.valid {
			t.Fatalf("Line '%s' expected valid=%v, got %v", c.line, c.valid, ok)
		}
		if ok {
			if c.pattern != "" && rule.Pattern != c.pattern {
				t.Errorf("Line '%s' expected pattern %s, got %s", c.line, c.pattern, rule.Pattern)
			}
			if rule.IsAllow != c.isAllow {
				t.Errorf("Line '%s' expected isAllow=%v, got %v", c.line, c.isAllow, rule.IsAllow)
			}
			if rule.Important != c.important {
				t.Errorf("Line '%s' expected important=%v, got %v", c.line, c.important, rule.Important)
			}
			if rule.IsRegex != c.isRegex {
				t.Errorf("Line '%s' expected isRegex=%v, got %v", c.line, c.isRegex, rule.IsRegex)
			}
			if c.dnsType != 0 && rule.DNSType != c.dnsType {
				t.Errorf("Line '%s' expected dnsType=%d, got %d", c.line, c.dnsType, rule.DNSType)
			}
		}
	}
}

// 布隆过滤器与字典树已迁至 rust/diting-filter-core（单测见 src/bloom.rs、src/trie.rs），
// 这里只保留穿过原生内核的行为断言。

func TestDomainTrie(t *testing.T) {
	matcher := NewRuleMatcher()
	defer matcher.release()

	var rules []*ParsedRule
	for _, line := range []string{"||ad.com^", "|exact.com|"} {
		rule, ok := ParseRuleLine(line, "test")
		if !ok {
			t.Fatalf("规则未被解析: %q", line)
		}
		rules = append(rules, rule)
	}
	if err := matcher.BuildFromRules(rules); err != nil {
		t.Fatalf("BuildFromRules: %v", err)
	}

	// 子域与自身命中
	for _, domain := range []string{"ad.com", "sub.ad.com", "a.b.c.ad.com", "exact.com"} {
		if res := matcher.Match(domain, dns.TypeA); !res.Blocked {
			t.Errorf("Expected match for %s", domain)
		}
	}

	// 精确匹配与子域阻断、不匹配情况
	for _, domain := range []string{"sub.exact.com", "notad.com"} {
		if res := matcher.Match(domain, dns.TypeA); res.Blocked {
			t.Errorf("Should not match %s", domain)
		}
	}
}

func TestRuleMatcherPriority(t *testing.T) {
	rules := []*ParsedRule{
		{Raw: "||blocked.com^", Pattern: "blocked.com"},
		{Raw: "@@||allow.blocked.com^", Pattern: "allow.blocked.com", IsAllow: true},
		{Raw: "||important.allow.blocked.com^$important", Pattern: "important.allow.blocked.com", Important: true},
		{Raw: "@@||top.important.allow.blocked.com^$important", Pattern: "top.important.allow.blocked.com", IsAllow: true, Important: true},
		{Raw: "||ad*.wildcard-ad.com^", Pattern: "ad*.wildcard-ad.com", IsWildcard: true, Regex: buildWildcardRegex("ad*.wildcard-ad.com")},
	}

	matcher := NewRuleMatcher()
	defer matcher.release()
	if err := matcher.BuildFromRules(rules); err != nil {
		t.Fatalf("BuildFromRules: %v", err)
	}

	// 1. 常规黑名单
	res := matcher.Match("blocked.com", dns.TypeA)
	if !res.Blocked || res.Reason != "blacklist" {
		t.Errorf("blocked.com should be blacklisted, got %+v", res)
	}

	// 2. 常规白名单胜过常规黑名单
	res = matcher.Match("allow.blocked.com", dns.TypeA)
	if res.Blocked || res.Reason != "whitelist" {
		t.Errorf("allow.blocked.com should be whitelisted, got %+v", res)
	}

	// 3. $important 黑名单胜过常规白名单
	res = matcher.Match("important.allow.blocked.com", dns.TypeA)
	if !res.Blocked || res.Reason != "important_block" {
		t.Errorf("important.allow.blocked.com should be important_block, got %+v", res)
	}

	// 4. $important 白名单胜过 $important 黑名单
	res = matcher.Match("top.important.allow.blocked.com", dns.TypeA)
	if res.Blocked || res.Reason != "important_allow" {
		t.Errorf("top.important.allow.blocked.com should be important_allow, got %+v", res)
	}

	// 5. 通配符匹配
	res = matcher.Match("ad123.wildcard-ad.com", dns.TypeA)
	if !res.Blocked || res.Reason != "wildcard_block" {
		t.Errorf("ad123.wildcard-ad.com should be wildcard_block, got %+v", res)
	}

	// 6. 干净域名
	res = matcher.Match("clean.example.com", dns.TypeA)
	if res.Blocked || res.Action != "pass" {
		t.Errorf("clean.example.com should pass, got %+v", res)
	}
}

func TestRuleEngine(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := DefaultFilterConfig()
	cfg.DataDir = tmpDir
	cfg.Lists = []FilterList{} // 测试时不预拉取外网
	cfg.CustomRules = []string{
		"||bad-banner.com^",
		"@@||good.bad-banner.com^",
	}

	engine := NewRuleEngine(cfg)
	defer engine.Close()

	if !engine.IsEnabled() {
		t.Fatalf("Engine should be enabled by default")
	}

	// 匹配测试
	res := engine.Match("bad-banner.com", dns.TypeA)
	if !res.Blocked {
		t.Errorf("bad-banner.com should be blocked")
	}

	res = engine.Match("good.bad-banner.com", dns.TypeA)
	if res.Blocked {
		t.Errorf("good.bad-banner.com should be allowed")
	}

	res = engine.Match("clean.com", dns.TypeA)
	if res.Blocked {
		t.Errorf("clean.com should pass")
	}

	// 统计测试
	stats := engine.GetStats()
	if stats.TotalQueries < 3 || stats.BlockedQueries != 1 || stats.AllowedQueries != 1 {
		t.Errorf("Stats mismatch: %+v", stats)
	}

	// 更新自定义规则
	newRules := []string{"||another-ad.com^"}
	if err := engine.SetCustomRules(newRules); err != nil {
		t.Fatalf("SetCustomRules error: %v", err)
	}
	res = engine.Match("another-ad.com", dns.TypeA)
	if !res.Blocked {
		t.Errorf("another-ad.com should be blocked after rule update")
	}
}

func TestRuleParser_EdgeCases(t *testing.T) {
	// 1. 测试以 | 结尾的精确匹配规则
	rule, ok := ParseRuleLine("example.com|", "test")
	if !ok || rule == nil || rule.Pattern != "example.com" || !rule.IsExact {
		t.Errorf("example.com| should be parsed as exact match rule, got %+v, ok=%v", rule, ok)
	}

	// 2. 纯网页资源修饰符规则应在 DNS 过滤阶段安全忽略
	webRules := []string{
		"||cdn.example.com^$image",
		"||cdn.example.com^$script",
		"||cdn.example.com^$stylesheet,font",
		"||cdn.example.com^$domain=foo.com",
		"||cdn.example.com^$third-party",
	}
	for _, wr := range webRules {
		r, ok := ParseRuleLine(wr, "test")
		if ok || r != nil {
			t.Errorf("Web-only rule %s should be safely skipped at DNS level, got %+v", wr, r)
		}
	}

	// 3. /etc/hosts 单行多域名解析
	hostsContent := "0.0.0.0 host1.com host2.com  host3.com # comment\n"
	parsed, err := ParseRules(strings.NewReader(hostsContent), "hosts-test")
	if err != nil {
		t.Fatalf("ParseRules error: %v", err)
	}
	if len(parsed) != 3 {
		t.Fatalf("Expected 3 rules from multi-host line, got %d", len(parsed))
	}
	expectedHosts := []string{"host1.com", "host2.com", "host3.com"}
	for i, h := range expectedHosts {
		if parsed[i].Pattern != h {
			t.Errorf("Host %d expected %s, got %s", i, h, parsed[i].Pattern)
		}
	}
}

func TestRuleMatcherPriority_WildcardAndRegexExceptions(t *testing.T) {
	rules := []*ParsedRule{
		// 常规黑名单
		{Raw: "||blocked.com^", Pattern: "blocked.com"},
		// 通配符白名单 (必须覆盖常规黑名单)
		{Raw: "@@||*.blocked.com^", Pattern: "*.blocked.com", IsAllow: true, IsWildcard: true, Regex: buildWildcardRegex("*.blocked.com")},
		// 正则白名单 (必须覆盖常规黑名单)
		{Raw: "@@/^safe[0-9]+\\.blocked\\.com$/", Pattern: "^safe[0-9]+\\.blocked\\.com$", IsAllow: true, IsRegex: true, Regex: regexp.MustCompile("(?i)^safe[0-9]+\\.blocked\\.com$")},
		// 重要黑名单通配符 (必须覆盖常规白名单)
		{Raw: "||*malware*.com^$important", Pattern: "*malware*.com", Important: true, IsWildcard: true, Regex: buildWildcardRegex("*malware*.com")},
		// 常规白名单
		{Raw: "@@||not-malware.com^", Pattern: "not-malware.com", IsAllow: true},
	}

	matcher := NewRuleMatcher()
	defer matcher.release()
	if err := matcher.BuildFromRules(rules); err != nil {
		t.Fatalf("BuildFromRules: %v", err)
	}

	// 1. 常规黑名单命中
	res := matcher.Match("blocked.com", dns.TypeA)
	if !res.Blocked || res.Reason != "blacklist" {
		t.Errorf("blocked.com should be blacklisted, got %+v", res)
	}

	// 2. 通配符白名单胜过常规黑名单
	res = matcher.Match("sub.blocked.com", dns.TypeA)
	if res.Blocked || res.Action != "allow" {
		t.Errorf("sub.blocked.com should be allowed by wildcard whitelist, got %+v", res)
	}

	// 3. 正则白名单胜过常规黑名单
	res = matcher.Match("safe1.blocked.com", dns.TypeA)
	if res.Blocked || res.Action != "allow" {
		t.Errorf("safe1.blocked.com should be allowed by regex whitelist, got %+v", res)
	}

	// 4. 重要黑名单通配符胜过常规白名单
	res = matcher.Match("not-malware.com", dns.TypeA)
	if !res.Blocked || res.Reason != "important_block" {
		t.Errorf("not-malware.com must be blocked by important wildcard rule, got %+v", res)
	}

	// 5. ANY 查询应匹配有 dnstype 限制的规则
	restricted := NewRuleMatcher()
	defer restricted.release()
	if err := restricted.BuildFromRules([]*ParsedRule{
		{Raw: "||a-only.test^$dnstype=A", Pattern: "a-only.test", DNSType: dns.TypeA},
	}); err != nil {
		t.Fatalf("BuildFromRules: %v", err)
	}
	if res := restricted.Match("a-only.test", dns.TypeANY); !res.Blocked {
		t.Errorf("Type ANY query must match rule restricted to Type A, got %+v", res)
	}
	if res := restricted.Match("a-only.test", dns.TypeAAAA); res.Blocked {
		t.Errorf("AAAA query must not match a rule restricted to Type A, got %+v", res)
	}
}

func TestRuleEngine_ConfigMergeAndConcurrency(t *testing.T) {
	tmpDir := t.TempDir()
	cfg := DefaultFilterConfig()
	cfg.DataDir = tmpDir
	cfg.CustomRules = []string{"||ad1.com^", "||ad2.com^"}

	engine := NewRuleEngine(cfg)
	defer engine.Close()

	// 部分更新测试: 仅更新 blockMode，不应清空 CustomRules
	partialCfg := FilterConfig{
		BlockMode: BlockModeNXDOMAIN,
	}
	if err := engine.UpdateConfig(partialCfg); err != nil {
		t.Fatalf("UpdateConfig error: %v", err)
	}

	currentCfg := engine.GetConfig()
	if len(currentCfg.CustomRules) != 2 {
		t.Fatalf("Partial config update wiped CustomRules! Expected 2, got %d", len(currentCfg.CustomRules))
	}
	if currentCfg.BlockMode != BlockModeNXDOMAIN {
		t.Errorf("BlockMode expected %s, got %s", BlockModeNXDOMAIN, currentCfg.BlockMode)
	}

	// 并发查询与规则热更新压力测试
	done := make(chan struct{})
	go func() {
		for i := 0; i < 50; i++ {
			_ = engine.SetCustomRules([]string{"||concurrent-ad.com^"})
			engine.SetEnabled(i%2 == 0)
			time.Sleep(1 * time.Millisecond)
		}
		close(done)
	}()

	for {
		select {
		case <-done:
			return
		default:
			_ = engine.Match("concurrent-ad.com", dns.TypeA)
			_ = engine.Match("clean.com", dns.TypeA)
		}
	}
}
