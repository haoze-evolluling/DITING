// mitm_filter.go keeps the MITM smart-filter surface the engine calls and delegates every decision
// to the Rust kernel in `rust/diting-mitm-core`.
//
// Responsibility split: the kernel owns the per-UID allow list, the `path.Match` exclusion
// patterns, the sensitive-host heuristics (banking, payment, identity endpoints), the automatic
// blacklist with its failure streaks, and the persistent blacklist file. Go keeps the log lines
// and the handle lifecycle; there is no second copy of any rule here.
//
// The kernel is required for MITM: `NewMitmFilter` fails without it, `StartStackMitm` fails with
// it, and the engine runs without interception. That is the conservative side of the old
// behaviour — nothing gets decrypted — and it is loud instead of silently starting to intercept
// endpoints the filter used to skip.
package tunnel

import (
	"runtime"
	"time"
)

// MitmFilter is the MITM smart filter.
type MitmFilter struct {
	native *nativeMitmFilter
}

// mitmReport is one decision report from the kernel; see rust/diting-mitm-core/src/payload.rs.
type mitmReport struct {
	// recorded reports that the failure streak was counted.
	recorded bool
	count    uint32
	// threshold is the streak length that blacklists the host.
	threshold uint32
	// host is the normalized host the kernel decided on.
	host string
	// blacklisted reports that the host is blacklisted after the call, whether this call did it
	// or an earlier one did.
	blacklisted bool
	// added reports that this call wrote the entry, i.e. that there is something to log.
	added  bool
	reason string
	ttlMs  int64
	// writeError is set when the entry could not be appended to the blacklist file.
	writeError string
}

// NewMitmFilter opens a filter handle.
func NewMitmFilter() (*MitmFilter, error) {
	native, err := newNativeMitmFilter()
	if err != nil {
		return nil, err
	}
	filter := &MitmFilter{native: native}
	// The engine drops its pointer in StopStackMitm; the handle and its state go with it.
	runtime.SetFinalizer(filter, func(f *MitmFilter) {
		if f != nil {
			f.native.free()
		}
	})
	return filter, nil
}

// mitmNow is the wall clock the kernel compares against; the kernel has no clock of its own.
func mitmNow() int64 {
	return time.Now().UnixMilli()
}

// logMitmBlacklisted prints the two lines the Go implementation printed when a host was
// blacklisted: the entry itself and, when the file append failed, the durability warning.
func logMitmBlacklisted(report mitmReport) {
	logf("MITM Filter: auto-blacklisted '%s' (%s, TTL=%v)",
		report.host, report.reason, time.Duration(report.ttlMs)*time.Millisecond)
	if report.writeError != "" {
		logf("MITM Filter: WARNING — cannot persist blacklist entry '%s': %v",
			report.host, report.writeError)
	}
}

// SetAllowedUIDs replaces the allow list from a CSV (the Kotlin side sends comma-separated UIDs)
// and returns how many apps are now intercepted. Only the digit characters of each element count,
// which is what the Go parser did.
func (f *MitmFilter) SetAllowedUIDs(uidsCsv string) int {
	if f == nil || f.native == nil {
		return 0
	}
	count := f.native.setAllowedUIDs(uidsCsv)
	logf("MITM Filter: updated allowed UIDs (%d apps)", count)
	return count
}

// IsUIDAllowed reports whether flows of `uid` may be intercepted.
func (f *MitmFilter) IsUIDAllowed(uid int) bool {
	if f == nil || f.native == nil {
		return false
	}
	return f.native.isUIDAllowed(int64(uid))
}

// HasAllowedUIDs reports whether any app is under strict interception.
func (f *MitmFilter) HasAllowedUIDs() bool {
	if f == nil || f.native == nil {
		return false
	}
	return f.native.hasAllowedUIDs()
}

// SetHttpsBypassRules replaces the exclusion patterns from a multi-line text (`#` and `//`
// comments and blank lines are dropped by the kernel) and returns how many rules were kept.
func (f *MitmFilter) SetHttpsBypassRules(content string) int {
	if f == nil || f.native == nil {
		return 0
	}
	count := f.native.setBypassRules(content)
	logf("MITM Filter: loaded %d HTTPS bypass rules", count)
	return count
}

// SetExtraPassthroughSuffixes is the entry point the platform channel uses for the same list.
func (f *MitmFilter) SetExtraPassthroughSuffixes(content string) int {
	return f.SetHttpsBypassRules(content)
}

// IsInterceptionAllowed reports whether `host` may be decrypted. A blacklisted or excluded host,
// a sensitive one (banking, payment, identity) and a bare address are all refused.
func (f *MitmFilter) IsInterceptionAllowed(host string) bool {
	if f == nil || f.native == nil {
		return false
	}
	return f.native.allowsInterception(host, mitmNow())
}

// RecordFailure counts a TLS handshake failure and reports whether the host was blacklisted by
// this call. Three failures in ten minutes are enough, two when the client rejected our
// certificate.
func (f *MitmFilter) RecordFailure(host string, err error) bool {
	if f == nil || f.native == nil || err == nil {
		return false
	}
	report := f.native.recordFailure(host, err.Error(), mitmNow())
	if !report.recorded {
		return false
	}
	if report.blacklisted {
		// Only a newly written entry has something new to say; a host that crossed the threshold
		// earlier is already listed and already logged.
		if report.added {
			logMitmBlacklisted(report)
		}
		return true
	}
	logf("MITM Filter: recorded TLS failure for '%s' (%d/%d): %v",
		report.host, report.count, report.threshold, err)
	return false
}

// BlacklistDomain keeps a host out of the MITM path for a week.
func (f *MitmFilter) BlacklistDomain(host string) {
	f.BlacklistDomainWithReason(host, "pinning")
}

// BlacklistDomainWithReason is BlacklistDomain with a reason for the log and the file line.
func (f *MitmFilter) BlacklistDomainWithReason(host, reason string) {
	if f == nil || f.native == nil {
		return
	}
	report, added := f.native.blacklist(host, reason, mitmNow())
	if !added {
		return
	}
	logMitmBlacklisted(report)
}

// ClearBlacklist drops every blacklist entry and failure streak, and truncates the file.
func (f *MitmFilter) ClearBlacklist() {
	if f == nil || f.native == nil {
		return
	}
	f.native.clear()
	logf("MITM Filter: cleared auto-blacklist")
}

// RemoveFromBlacklist forgets one host in memory; the file keeps the line, like before.
func (f *MitmFilter) RemoveFromBlacklist(host string) {
	if f == nil || f.native == nil {
		return
	}
	f.native.remove(host)
}

// LoadPersistentBlacklist reads the blacklist file and reports how many live entries it held.
func (f *MitmFilter) LoadPersistentBlacklist(path string) int {
	if f == nil || f.native == nil {
		return 0
	}
	loaded := f.native.loadPersistent(path, mitmNow())
	logf("MITM Filter: persistent blacklist at %s (%d active entries loaded)", path, loaded)
	return loaded
}

// GetBlacklistCount returns the live entries, for the settings screen.
func (f *MitmFilter) GetBlacklistCount() int {
	if f == nil || f.native == nil {
		return 0
	}
	return f.native.blacklistCount(mitmNow())
}
