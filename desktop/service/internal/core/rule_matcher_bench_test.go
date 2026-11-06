package core

import (
	"fmt"
	"regexp"
	"testing"

	"github.com/miekg/dns"
)

// benchRuleSet 造一份接近真实订阅的规则集：纯域名、通配、正则、例外与重写混排。
func benchRuleSet(size int) []*ParsedRule {
	rules := make([]*ParsedRule, 0, size)
	for i := 0; i < size; i++ {
		switch i % 10 {
		case 0:
			rules = append(rules, &ParsedRule{
				Raw:     fmt.Sprintf("@@||allow%d.example.com^", i),
				Pattern: fmt.Sprintf("allow%d.example.com", i),
				IsAllow: true,
				Source:  "bench",
			})
		case 1:
			pattern := fmt.Sprintf("*.ads%d.example.com", i)
			rules = append(rules, &ParsedRule{
				Raw:        "||" + pattern + "^",
				Pattern:    pattern,
				IsWildcard: true,
				Regex:      buildWildcardRegex(pattern),
				Source:     "bench",
			})
		case 2:
			body := fmt.Sprintf("^tracker[0-9]+\\.rx%d\\.example\\.com$", i)
			rules = append(rules, &ParsedRule{
				Raw:     "/" + body + "/",
				Pattern: body,
				IsRegex: true,
				Regex:   regexp.MustCompile("(?i)" + body),
				Source:  "bench",
			})
		case 3:
			rules = append(rules, &ParsedRule{
				Raw:     fmt.Sprintf("||only%d.example.com^$dnstype=AAAA", i),
				Pattern: fmt.Sprintf("only%d.example.com", i),
				DNSType: dns.TypeAAAA,
				Source:  "bench",
			})
		case 4:
			rules = append(rules, &ParsedRule{
				Raw:       fmt.Sprintf("||excluded%d.example.com^$denyallow=cdn%d.example.com", i, i),
				Pattern:   fmt.Sprintf("excluded%d.example.com", i),
				DenyAllow: []string{fmt.Sprintf("cdn%d.example.com", i)},
				Source:    "bench",
			})
		case 5:
			rules = append(rules, &ParsedRule{
				Raw:     fmt.Sprintf("||rw%d.example.com^$dnsrewrite=127.0.0.1", i),
				Pattern: fmt.Sprintf("rw%d.example.com", i),
				Rewrite: &RewriteAction{RCode: dns.RcodeSuccess, RRType: dns.TypeA, Value: "127.0.0.1"},
				Source:  "bench",
			})
		default:
			rules = append(rules, &ParsedRule{
				Raw:     fmt.Sprintf("||blocked%d.example.com^", i),
				Pattern: fmt.Sprintf("blocked%d.example.com", i),
				Source:  "bench",
			})
		}
	}
	return rules
}

// benchRuleSetRealistic 造一份更接近线上订阅比例的规则集：绝大多数是纯域名，
// 通配与正则只占少量（合成集里的 10%/10% 是刻意构造的最坏情况）。
func benchRuleSetRealistic(size int) []*ParsedRule {
	rules := make([]*ParsedRule, 0, size)
	for i := 0; i < size; i++ {
		switch {
		case i%1000 == 0:
			body := fmt.Sprintf(`^tracker[0-9]+\.rx%d\.example\.com$`, i)
			rules = append(rules, &ParsedRule{
				Raw:     "/" + body + "/",
				Pattern: body,
				IsRegex: true,
				Regex:   regexp.MustCompile("(?i)" + body),
				Source:  "bench",
			})
		case i%100 == 1:
			pattern := fmt.Sprintf("*.ads%d.example.com", i)
			rules = append(rules, &ParsedRule{
				Raw:        "||" + pattern + "^",
				Pattern:    pattern,
				IsWildcard: true,
				Regex:      buildWildcardRegex(pattern),
				Source:     "bench",
			})
		case i%50 == 2:
			rules = append(rules, &ParsedRule{
				Raw:     fmt.Sprintf("@@||allow%d.example.com^", i),
				Pattern: fmt.Sprintf("allow%d.example.com", i),
				IsAllow: true,
				Source:  "bench",
			})
		default:
			rules = append(rules, &ParsedRule{
				Raw:     fmt.Sprintf("||blocked%d.example.com^", i),
				Pattern: fmt.Sprintf("blocked%d.example.com", i),
				Source:  "bench",
			})
		}
	}
	return rules
}

// benchDomains 造一批查询名：干净域名、字典树命中、通配命中、正则命中、重写命中各占一部分。
func benchDomains(size int, rules int) []string {
	domains := make([]string, 0, size)
	for i := 0; i < size; i++ {
		index := (i * 7) % rules
		switch i % 5 {
		case 0:
			domains = append(domains, fmt.Sprintf("clean%d.other.example.net", i))
		case 1:
			domains = append(domains, fmt.Sprintf("sub.blocked%d.example.com", index))
		case 2:
			domains = append(domains, fmt.Sprintf("x.ads%d.example.com", index))
		case 3:
			domains = append(domains, fmt.Sprintf("tracker%d.rx%d.example.com", i, index))
		default:
			domains = append(domains, fmt.Sprintf("rw%d.example.com", index))
		}
	}
	return domains
}

func BenchmarkRuleMatcherMatch(b *testing.B) {
	rules := benchRuleSet(20000)
	matcher := NewRuleMatcher()
	defer matcher.release()
	if err := matcher.BuildFromRules(rules); err != nil {
		b.Fatalf("BuildFromRules: %v", err)
	}
	domains := benchDomains(1024, len(rules))

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		matcher.Match(domains[i%len(domains)], dns.TypeA)
	}
}

func BenchmarkRuleMatcherMatchRealistic(b *testing.B) {
	rules := benchRuleSetRealistic(20000)
	matcher := NewRuleMatcher()
	defer matcher.release()
	if err := matcher.BuildFromRules(rules); err != nil {
		b.Fatalf("BuildFromRules: %v", err)
	}
	domains := benchDomains(1024, len(rules))

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		matcher.Match(domains[i%len(domains)], dns.TypeA)
	}
}

func BenchmarkRuleMatcherBuild(b *testing.B) {
	rules := benchRuleSet(20000)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		matcher := NewRuleMatcher()
		if err := matcher.BuildFromRules(rules); err != nil {
			b.Fatalf("BuildFromRules: %v", err)
		}
		matcher.release()
	}
}
