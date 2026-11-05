// policy_snapshot.go is one immutable rule set served by the Rust policy kernel.
//
// The Go side keeps only the kernel handle and the hasRules bit the call sites branch on: domain
// normalization, the rule tables, the wildcard index, the DTRI lookup, the seven-level priority
// walk and the decision cache all live in the kernel. `evaluate` is one call into it, cache hit or
// not.

package tunnel

type policySnapshot struct {
	hasRules bool

	// native is the Rust policy kernel for this snapshot. It is nil only for the empty snapshot a
	// fresh engine publishes before the first rule set arrives.
	native *nativePolicy
}

// newPolicySnapshot wraps a built kernel handle. The payload's `filterEnabled` switch is the
// kernel's business too, so the only thing Go reads from the flags is whether any rule exists.
func newPolicySnapshot(native *nativePolicy) *policySnapshot {
	snap := &policySnapshot{native: native}
	if native != nil {
		snap.hasRules = native.flags&nativeFlagHasRules != 0
	}
	return snap
}

// evaluate answers one query through the kernel's decision cache and rule tables.
func (s *policySnapshot) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string) {
	if s == nil || !s.hasRules || s.native == nil {
		return false, ""
	}
	return s.native.evaluate(domain, appName, qtype)
}

// evaluateUncached runs the same walk and normalization without touching the decision cache. Used
// by the tests and benchmarks to prove a cache hit never changes an answer.
func (s *policySnapshot) evaluateUncached(domain, appName string, qtype uint16) (bool, string) {
	if s == nil || !s.hasRules || s.native == nil {
		return false, ""
	}
	return s.native.evaluateUncached(domain, appName, qtype)
}

// prewarmFrom re-evaluates the previous snapshot's hottest keys against s, so hot domains stay
// fast after a rule reload. The kernel decides whether the two snapshots can share their keys;
// Go only runs it in the background while the old handle is still alive.
func (s *policySnapshot) prewarmFrom(prev *policySnapshot) {
	if s == nil || prev == nil || s.native == nil || prev.native == nil {
		return
	}
	s.native.prewarm(prev.native)
}
