package tunnel

import (
	"regexp"
	"regexp/syntax"
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

// regexAnchoredPrefix returns the ASCII literal that every match of pattern must
// start with (e.g. "^ads\." -> "ads."), or "" when there is none. It is only a
// prefilter: callers still run the regex, and compare case-insensitively.
func regexAnchoredPrefix(pattern string) string {
	re, err := syntax.Parse(pattern, syntax.Perl)
	if err != nil {
		return ""
	}
	re = re.Simplify()
	if re.Op != syntax.OpConcat || len(re.Sub) < 2 || re.Sub[0].Op != syntax.OpBeginText {
		return ""
	}
	lit := re.Sub[1]
	if lit.Op != syntax.OpLiteral {
		return ""
	}
	var sb strings.Builder
	for _, r := range lit.Rune {
		if r >= 0x80 {
			break
		}
		sb.WriteRune(r)
	}
	return strings.ToLower(sb.String())
}

// mayMatchPrefix reports whether domain can satisfy an anchored literal prefix.
// Non-ASCII domains are never rejected, because regex case folding is broader
// than ASCII EqualFold there.
func mayMatchPrefix(domain, prefix string) bool {
	if prefix == "" || !isASCII(domain) {
		return true
	}
	return len(domain) >= len(prefix) && strings.EqualFold(domain[:len(prefix)], prefix)
}
