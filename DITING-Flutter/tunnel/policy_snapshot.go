package tunnel

import (
	"regexp"
	"strings"
)

type appRuleBucket struct {
	allow     map[string]struct{}
	block     map[string]string
	important map[string]string

	allowWildcards     *wildcardIndex
	blockWildcards     *wildcardIndex
	importantWildcards *wildcardIndex
}

type invertedRule struct {
	pattern      string
	source       string
	important    bool
	excludedApps map[string]struct{}
	wildcard     *wildcardMatcher
}

type specialRule struct {
	pattern       string
	source        string
	important     bool
	isAllow       bool
	appScope      map[string]struct{}
	appInverted   bool
	denyallow     []string
	isRegex       bool
	regex         *regexp.Regexp
	rxPrefix      string
	wildcard      *wildcardMatcher
	includeQtypes map[uint16]struct{}
	excludeQtypes map[uint16]struct{}
}

func (r *specialRule) matches(domain, appName string, qtype uint16) bool {
	if r == nil {
		return false
	}

	// 1. DNS query type check (if rule specifies dnsType)
	if len(r.excludeQtypes) > 0 || len(r.includeQtypes) > 0 {
		if qtype == 0 {
			return false
		}
		if len(r.excludeQtypes) > 0 {
			if _, excluded := r.excludeQtypes[qtype]; excluded {
				return false
			}
		}
		if len(r.includeQtypes) > 0 {
			if _, included := r.includeQtypes[qtype]; !included {
				return false
			}
		}
	}

	// 2. App scope check
	if len(r.appScope) > 0 {
		if r.appInverted {
			if appName != "" {
				if _, excluded := r.appScope[appName]; excluded {
					return false
				}
			}
		} else {
			if appName == "" {
				return false
			}
			if _, included := r.appScope[appName]; !included {
				return false
			}
		}
	}

	// 3. Denyallow check: if domain or any suffix matches denyallow exception, rule is exempted
	for _, exc := range r.denyallow {
		if domain == exc || strings.HasSuffix(domain, "."+exc) {
			return false
		}
	}

	// 4. Pattern check (regex, wildcard, or domain suffix)
	if r.isRegex {
		if r.regex == nil || !mayMatchPrefix(domain, r.rxPrefix) || !r.regex.MatchString(domain) {
			return false
		}
	} else if r.wildcard != nil {
		if !r.wildcard.matches(domain) {
			return false
		}
	} else {
		if !matchSingleDomainOrSuffix(domain, r.pattern) {
			return false
		}
	}

	return true
}

type policySnapshot struct {
	filterEnabled bool
	hasRules      bool

	globalImportant          map[string]string
	globalImportantWildcards *wildcardIndex
	importantInverted        []invertedRule
	importantBlockTrie       *dtriReader

	globalAllow          map[string]struct{}
	globalAllowWildcards *wildcardIndex
	allowInverted        []invertedRule
	importantAllowTrie   *dtriReader
	allowTrie            *dtriReader

	globalBlock          map[string]string
	globalBlockWildcards *wildcardIndex
	blockInverted        []invertedRule
	blockTrie            *dtriReader

	importantAppBlockSpecial    []*specialRule
	importantGlobalBlockSpecial []*specialRule
	appAllowSpecial             []*specialRule
	globalAllowSpecial          []*specialRule
	appBlockSpecial             []*specialRule
	globalBlockSpecial          []*specialRule

	disabledRules map[string]struct{}

	appBuckets map[string]*appRuleBucket

	// appSensitive/qtypeSensitive record whether any rule looks at the app
	// name or query type; the decision cache drops dimensions nobody reads.
	appSensitive   bool
	qtypeSensitive bool
	cache          *decisionCache
}

// evaluate executes the 7-level rule evaluation priority:
// 1. App-specific $important blocking rules (exact match, wildcards, and special rules).
// 2. Global $important blocking rules (including inverted app exclusions, subscription important tries, and special rules).
// 3. App-specific whitelist rules (@@, exact, wildcards, and special rules).
// 4. Global whitelist rules (@@, including inverted exclusions, subscription allowTrie, and special rules).
// 5. App-specific normal blocking rules (including full-app blocks via *$app=pkg and special rules).
// 6. Global normal blocking rules (including inverted exclusions, subscription blockTrie, and special rules).
// 7. Default pass (no rules matched).
func (s *policySnapshot) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string) {
	if s == nil || !s.filterEnabled {
		return false, ""
	}
	domain = normalizePolicyDomain(domain)
	if domain == "" {
		return false, ""
	}
	appName = strings.TrimSpace(appName)
	if s.cache == nil || !s.hasRules {
		return s.evaluateNormalized(domain, appName, qtype)
	}
	key := s.cacheKey(domain, appName, qtype)
	if blocked, reason, ok := s.cache.get(key); ok {
		return blocked, reason
	}
	blocked, reason = s.evaluateNormalized(domain, appName, qtype)
	s.cache.put(key, blocked, reason, 1)
	return blocked, reason
}

// evaluateUncached runs the full rule walk without touching the decision cache.
func (s *policySnapshot) evaluateUncached(domain, appName string, qtype uint16) (bool, string) {
	if s == nil || !s.filterEnabled {
		return false, ""
	}
	domain = normalizePolicyDomain(domain)
	if domain == "" {
		return false, ""
	}
	return s.evaluateNormalized(domain, strings.TrimSpace(appName), qtype)
}

// normalizePolicyDomain lower-cases and trims domain, skipping the
// allocations when it is already in canonical form (the common case).
func normalizePolicyDomain(domain string) string {
	canonical := true
	for i := 0; i < len(domain); i++ {
		if c := domain[i]; c >= 'A' && c <= 'Z' || c >= 0x80 || c <= ' ' {
			canonical = false
			break
		}
	}
	if !canonical {
		domain = strings.ToLower(strings.TrimSpace(domain))
	}
	return strings.TrimSuffix(domain, ".")
}

func (s *policySnapshot) evaluateNormalized(domain, appName string, qtype uint16) (blocked bool, reason string) {
	// Level 1: App-specific $important blocking rules
	if appName != "" && len(s.appBuckets) > 0 {
		if bucket, ok := s.appBuckets[appName]; ok {
			if r, hit := matchDomainOrSuffix(domain, bucket.important); hit {
				return true, r
			}
			if pat, hit := bucket.importantWildcards.match(domain); hit {
				return true, pat
			}
		}
	}
	for _, r := range s.importantAppBlockSpecial {
		if r.matches(domain, appName, qtype) {
			return true, r.pattern
		}
	}

	// Level 2: Global $important blocking rules
	for _, inv := range s.importantInverted {
		if appName != "" {
			if _, excluded := inv.excludedApps[appName]; excluded {
				continue
			}
		}
		if inv.wildcard != nil {
			if inv.wildcard.matches(domain) {
				return true, inv.pattern
			}
		} else if matchSingleDomainOrSuffix(domain, inv.pattern) {
			return true, inv.pattern
		}
	}

	for _, r := range s.importantGlobalBlockSpecial {
		if r.matches(domain, appName, qtype) {
			return true, r.pattern
		}
	}

	if r, hit := matchDomainOrSuffix(domain, s.globalImportant); hit {
		return true, r
	}
	if pat, hit := s.globalImportantWildcards.match(domain); hit {
		return true, pat
	}
	if s.importantBlockTrie != nil {
		if hit, src := s.importantBlockTrie.containsOrParentWithDisabled(domain, s.disabledRules); hit {
			return true, src
		}
	}

	// Level 3: App-specific whitelist rules (@@)
	if appName != "" && len(s.appBuckets) > 0 {
		if bucket, ok := s.appBuckets[appName]; ok {
			if matchDomainOrSuffixSet(domain, bucket.allow) {
				return false, "__ALLOW__"
			}
			if _, hit := bucket.allowWildcards.match(domain); hit {
				return false, "__ALLOW__"
			}
		}
	}
	for _, r := range s.appAllowSpecial {
		if r.matches(domain, appName, qtype) {
			return false, "__ALLOW__"
		}
	}

	// Level 4: Global whitelist rules (@@)
	for _, inv := range s.allowInverted {
		if appName != "" {
			if _, excluded := inv.excludedApps[appName]; excluded {
				continue
			}
		}
		if inv.wildcard != nil {
			if inv.wildcard.matches(domain) {
				return false, "__ALLOW__"
			}
		} else if matchSingleDomainOrSuffix(domain, inv.pattern) {
			return false, "__ALLOW__"
		}
	}

	for _, r := range s.globalAllowSpecial {
		if r.matches(domain, appName, qtype) {
			return false, "__ALLOW__"
		}
	}

	if matchDomainOrSuffixSet(domain, s.globalAllow) {
		return false, "__ALLOW__"
	}
	if _, hit := s.globalAllowWildcards.match(domain); hit {
		return false, "__ALLOW__"
	}

	if s.importantAllowTrie != nil {
		if hit, _ := s.importantAllowTrie.containsOrParent(domain); hit {
			return false, "__ALLOW__"
		}
	}
	if s.allowTrie != nil {
		if hit, _ := s.allowTrie.containsOrParent(domain); hit {
			return false, "__ALLOW__"
		}
	}

	// Level 5: App-specific normal blocking rules
	if appName != "" && len(s.appBuckets) > 0 {
		if bucket, ok := s.appBuckets[appName]; ok {
			if r, hit := matchDomainOrSuffix(domain, bucket.block); hit {
				return true, r
			}
			if pat, hit := bucket.blockWildcards.match(domain); hit {
				return true, pat
			}
		}
	}
	for _, r := range s.appBlockSpecial {
		if r.matches(domain, appName, qtype) {
			return true, r.pattern
		}
	}

	// Level 6: Global normal blocking rules
	for _, inv := range s.blockInverted {
		if appName != "" {
			if _, excluded := inv.excludedApps[appName]; excluded {
				continue
			}
		}
		if inv.wildcard != nil {
			if inv.wildcard.matches(domain) {
				return true, inv.pattern
			}
		} else if matchSingleDomainOrSuffix(domain, inv.pattern) {
			return true, inv.pattern
		}
	}

	for _, r := range s.globalBlockSpecial {
		if r.matches(domain, appName, qtype) {
			return true, r.pattern
		}
	}

	if r, hit := matchDomainOrSuffix(domain, s.globalBlock); hit {
		return true, r
	}
	if pat, hit := s.globalBlockWildcards.match(domain); hit {
		return true, pat
	}
	if s.blockTrie != nil {
		if hit, src := s.blockTrie.containsOrParentWithDisabled(domain, s.disabledRules); hit {
			return true, src
		}
	}

	// Level 7: Default pass
	return false, ""
}
