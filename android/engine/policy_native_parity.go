// policy_native_parity.go cross-checks the Rust policy kernel against the Go walk.
//
// Both implementations are built for every snapshot, so the cheapest possible guard against a
// silent divergence is to ask both of them the same questions before the snapshot is published.
// The probe set is derived from the rules that were just loaded (their own patterns, app scopes and
// query types), so drift in the real rule set - not just in a synthetic unit-test fixture - is
// caught on the device that would have served it.
//
// A disagreement drops the native path for this snapshot only: log once, keep running on Go. This
// is what makes "the native path cannot change an answer" true rather than aspirational; the
// exhaustive version of the same check is the randomized parity test in policy_native_test.go.

package tunnel

import (
	"errors"
	"fmt"
	"strings"
)

// errNativePolicyUnavailable is what the `!cgo` stub returns and what a build without the shipped
// library produces; it is reported as "not available" rather than as a fault.
var errNativePolicyUnavailable = errors.New("native policy kernel unavailable")

// policyProbeBudget caps how many (domain, app, qtype) triples a snapshot apply spends on the
// cross-check. Each one is two rule walks, so this stays in the microsecond range.
const policyProbeBudget = 96

type policyProbe struct {
	domain string
	app    string
	qtype  uint16
}

// policyProbes derives the cross-check queries from the payload that was just applied.
func policyProbes(req *ruleSnapshotJSON) []policyProbe {
	domains := make([]string, 0, 32)
	seen := make(map[string]struct{})
	add := func(raw string) {
		raw = strings.ToLower(strings.TrimSpace(raw))
		raw = strings.TrimSuffix(raw, ".")
		if raw == "" {
			return
		}
		for _, candidate := range []string{raw, strings.ReplaceAll(raw, "*", "x")} {
			if candidate == "" || strings.Contains(candidate, "*") {
				continue
			}
			if _, exists := seen[candidate]; exists {
				continue
			}
			seen[candidate] = struct{}{}
			domains = append(domains, candidate)
		}
	}
	for _, list := range [][]string{req.GlobalBlock, req.GlobalAllow, req.GlobalImportant, req.DisabledRules} {
		for _, pattern := range list {
			add(pattern)
		}
	}
	for _, inverted := range req.InvertedBlock {
		add(inverted.Pattern)
	}
	for _, inverted := range req.InvertedAllow {
		add(inverted.Pattern)
	}
	for _, list := range [][]specialRuleConfigJSON{req.SpecialBlock, req.SpecialAllow} {
		for _, rule := range list {
			if !rule.IsRegex {
				add(rule.Pattern)
			}
			for _, app := range strings.Split(rule.AppScope, "|") {
				app = strings.ToLower(strings.TrimSpace(app))
				if app != "" {
					seen[app] = struct{}{}
				}
			}
		}
	}
	// Always probe a few domains that match nothing: a rule that only exists on one side shows up
	// as a false positive here.
	for _, domain := range []string{"example.com", "www.example.com", "ads.example.com", "a.b.c.d"} {
		add(domain)
	}
	if len(domains) > 24 {
		domains = domains[:24]
	}

	apps := make([]string, 0, 3)
	apps = append(apps, "")
	for pkg := range req.AppRules {
		pkg = strings.ToLower(strings.TrimSpace(pkg))
		if pkg != "" {
			apps = append(apps, pkg)
			break
		}
	}
	for _, list := range [][]specialRuleConfigJSON{req.SpecialBlock, req.SpecialAllow} {
		for _, rule := range list {
			for _, app := range strings.Split(rule.AppScope, "|") {
				app = strings.ToLower(strings.TrimSpace(app))
				if app != "" && len(apps) < 3 {
					apps = append(apps, app)
				}
			}
		}
	}

	probes := make([]policyProbe, 0, policyProbeBudget)
	for _, domain := range domains {
		for _, app := range apps {
			for _, qtype := range []uint16{1, 28} {
				if len(probes) >= policyProbeBudget {
					return probes
				}
				probes = append(probes, policyProbe{domain: domain, app: app, qtype: qtype})
			}
		}
	}
	return probes
}

// countRegexRules returns how many regex special rules survived parsing: the number the Rust side
// has to agree on, because accept-set differences cannot be detected any other way at build time.
func (s *policySnapshot) countRegexRules() int {
	count := 0
	for _, list := range [][]*specialRule{
		s.importantAppBlockSpecial, s.importantGlobalBlockSpecial, s.appAllowSpecial,
		s.globalAllowSpecial, s.appBlockSpecial, s.globalBlockSpecial,
	} {
		for _, rule := range list {
			if rule.isRegex {
				count++
			}
		}
	}
	return count
}

// attachNativePolicy builds the Rust snapshot for `snap` and keeps it only when both engines agree
// on the snapshot's shape and on every probe query.
func attachNativePolicy(snap *policySnapshot, jsonStr string, req *ruleSnapshotJSON) {
	native, err := newNativePolicy(jsonStr, snap.countRegexRules())
	if err != nil {
		if !errors.Is(err, errNativePolicyUnavailable) {
			logf("policyEngine: Rust policy snapshot not used: %v", err)
		}
		return
	}
	if mismatch := nativeFlagsMismatch(snap, native.flags); mismatch != "" {
		logf("policyEngine: Rust policy snapshot rejected (%s); keeping the Go engine", mismatch)
		native.release()
		return
	}
	if disagreement := nativeDisagreement(snap, native, policyProbes(req)); disagreement != "" {
		logf("policyEngine: Rust policy snapshot rejected (%s); keeping the Go engine", disagreement)
		native.release()
		return
	}
	snap.native = native
}

// nativeFlagsMismatch reports whether the two engines disagree on the snapshot's shape.
func nativeFlagsMismatch(snap *policySnapshot, flags uint32) string {
	want := uint32(0)
	if snap.hasRules {
		want |= nativeFlagHasRules
	}
	if snap.appSensitive {
		want |= nativeFlagAppSensitive
	}
	if snap.qtypeSensitive {
		want |= nativeFlagQtypeSensitive
	}
	if want != flags {
		return fmt.Sprintf("flags go=%02b rust=%02b", want, flags)
	}
	return ""
}

// evaluateReference is the Go answer with production semantics (the filter switch and the already
// normalized input) but without the decision cache and without the native path, which is exactly
// the pair the cross-check has to compare.
func (s *policySnapshot) evaluateReference(domain, appName string, qtype uint16) (bool, string) {
	if s == nil || !s.filterEnabled || domain == "" {
		return false, ""
	}
	return s.evaluateGo(domain, appName, qtype)
}

// nativeDisagreement returns a description of the first query the two engines answer differently,
// or "" when they agree on every probe.
func nativeDisagreement(snap *policySnapshot, native *nativePolicy, probes []policyProbe) string {
	for _, probe := range probes {
		wantBlocked, wantReason := snap.evaluateReference(probe.domain, probe.app, probe.qtype)
		gotBlocked, gotReason, ok := native.evaluate(probe.domain, probe.app, probe.qtype)
		if !ok {
			return "native evaluate failed during the cross-check"
		}
		if gotBlocked != wantBlocked || gotReason != wantReason {
			return fmt.Sprintf("domain=%q app=%q qtype=%d: go=(%v,%q) rust=(%v,%q)",
				probe.domain, probe.app, probe.qtype, wantBlocked, wantReason, gotBlocked, gotReason)
		}
	}
	return ""
}
