package tunnel

import (
	"regexp"
	"strings"
)

type wildcardMatcher struct {
	pattern    string
	baseDomain string
	isAll      bool
	regex      *regexp.Regexp
}

func newWildcardMatcher(pattern string) *wildcardMatcher {
	if pattern == "*" {
		return &wildcardMatcher{pattern: pattern, isAll: true}
	}
	var baseDomain string
	if strings.HasPrefix(pattern, "*.") && len(pattern) > 2 {
		baseDomain = strings.TrimSuffix(strings.ToLower(pattern[2:]), ".")
	}
	var sb strings.Builder
	sb.WriteString("^")
	for _, ch := range pattern {
		if ch == '*' {
			sb.WriteString(".*")
		} else {
			sb.WriteString(regexp.QuoteMeta(string(ch)))
		}
	}
	sb.WriteString("$")
	re, err := regexp.Compile("(?i)" + sb.String())
	if err != nil {
		return nil
	}
	return &wildcardMatcher{pattern: pattern, baseDomain: baseDomain, isAll: false, regex: re}
}

func (w *wildcardMatcher) matches(domain string) bool {
	if w == nil {
		return false
	}
	if w.isAll {
		return true
	}
	if w.baseDomain != "" && domain == w.baseDomain {
		return true
	}
	if w.regex == nil {
		return false
	}
	if w.regex.MatchString(domain) {
		return true
	}
	d := domain
	for {
		dot := strings.IndexByte(d, '.')
		if dot < 0 || dot >= len(d)-1 {
			break
		}
		d = d[dot+1:]
		if w.baseDomain != "" && d == w.baseDomain {
			return true
		}
		if w.regex.MatchString(d) {
			return true
		}
	}
	return false
}

func matchDomainOrSuffix(domain string, m map[string]string) (string, bool) {
	if len(m) == 0 {
		return "", false
	}
	if val, ok := m[domain]; ok {
		return val, true
	}
	d := domain
	for {
		pos := strings.IndexByte(d, '.')
		if pos < 0 || pos >= len(d)-1 {
			break
		}
		d = d[pos+1:]
		if val, ok := m[d]; ok {
			return val, true
		}
	}
	return "", false
}

func matchDomainOrSuffixSet(domain string, s map[string]struct{}) bool {
	if len(s) == 0 {
		return false
	}
	if _, ok := s[domain]; ok {
		return true
	}
	d := domain
	for {
		pos := strings.IndexByte(d, '.')
		if pos < 0 || pos >= len(d)-1 {
			break
		}
		d = d[pos+1:]
		if _, ok := s[d]; ok {
			return true
		}
	}
	return false
}

func matchSingleDomainOrSuffix(domain, pattern string) bool {
	if domain == pattern {
		return true
	}
	return strings.HasSuffix(domain, "."+pattern)
}
