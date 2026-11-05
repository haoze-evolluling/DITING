// policy_snapshot.go is one immutable rule set served by the Rust policy kernel.
//
// The Go side keeps only what the call site and the decision cache need: the filter switch, the
// snapshot shape flags and the kernel handle. The rule tables, the wildcard index, the DTRI lookup
// and the seven-level priority walk all live in the kernel; `evaluate` never walks a rule here.

package tunnel

import "strings"

type policySnapshot struct {
	filterEnabled bool
	hasRules      bool

	// appSensitive/qtypeSensitive come from the kernel's snapshot flags; the decision cache drops
	// dimensions no rule reads.
	appSensitive   bool
	qtypeSensitive bool
	cache          *decisionCache

	// native is the Rust policy kernel for this snapshot. It is nil only for the empty snapshot a
	// fresh engine publishes before the first rule set arrives.
	native *nativePolicy
}

// newPolicySnapshot wraps a built kernel handle. `filterEnabled` is the payload's switch, which
// the kernel does not report in its flags.
func newPolicySnapshot(native *nativePolicy, filterEnabled *bool) *policySnapshot {
	snap := &policySnapshot{
		filterEnabled: filterEnabled == nil || *filterEnabled,
		native:        native,
	}
	if native == nil {
		return snap
	}
	snap.hasRules = native.flags&nativeFlagHasRules != 0
	snap.appSensitive = native.flags&nativeFlagAppSensitive != 0
	snap.qtypeSensitive = native.flags&nativeFlagQtypeSensitive != 0
	if snap.filterEnabled && snap.hasRules {
		snap.cache = newDecisionCache()
	}
	return snap
}

// evaluate answers one query through the decision cache and the kernel.
func (s *policySnapshot) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string) {
	if s == nil || !s.filterEnabled || !s.hasRules || s.native == nil {
		return false, ""
	}
	domain = normalizePolicyDomain(domain)
	if domain == "" {
		return false, ""
	}
	appName = strings.TrimSpace(appName)
	if s.cache == nil {
		return s.native.evaluate(domain, appName, qtype)
	}
	key := s.cacheKey(domain, appName, qtype)
	if blocked, reason, ok := s.cache.get(key); ok {
		return blocked, reason
	}
	blocked, reason = s.native.evaluate(domain, appName, qtype)
	s.cache.put(key, blocked, reason, 1)
	return blocked, reason
}

// evaluateUncached runs the kernel without touching the decision cache.
func (s *policySnapshot) evaluateUncached(domain, appName string, qtype uint16) (bool, string) {
	if s == nil || !s.filterEnabled || !s.hasRules || s.native == nil {
		return false, ""
	}
	domain = normalizePolicyDomain(domain)
	if domain == "" {
		return false, ""
	}
	return s.native.evaluate(domain, strings.TrimSpace(appName), qtype)
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
