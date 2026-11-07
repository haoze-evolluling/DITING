// engine_app_allowlist.go implements per-UID domain authorization caching for strict application allowlist mode.
//
// Key Behaviors:
// - Authorization Lifetime: Destinations are usable only while their DNS TTL remains valid for the resolving app UID.
// - System Resolver Handling: Evaluates queries against all restricted UIDs to handle Android netd system
//   resolver queries dispatched under netd UID or UIDUnknown on behalf of client apps.
// - Expiration Pruning: Cached IP mappings are pruned automatically when size exceeds thresholds.
//
// Responsibility split (Rust kernel rust/diting-allowlist-core): the normalized allowed-domain
// sets, the suffix walk, the per-UID TTL grants, the answer fan-out and the pruning all live in
// the kernel. Go keeps the JSON config (`encoding/json` + `strconv`), the `dns.Msg` A/AAAA
// traversal and the `net.IP` loopback fast path. Every kernel call passes unix nanoseconds.
//
// If the kernel is unavailable, an engine with no configured rules behaves exactly as before; the
// UIDs the last config selected fail closed (DNS and connections denied, loopback still allowed)
// instead of silently allowing everything, while unselected apps keep their old path. There is no
// second matching implementation to fall back to.

package tunnel

import (
	"encoding/json"
	"net"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// appAllowlistEntry is the config shape handed to the kernel: a UID and its raw (un-normalized)
// domain list. A UID with an empty list is selected and may resolve nothing.
type appAllowlistEntry struct {
	uid     int
	domains []string
}

// allowlistRecord is one A/AAAA answer: the 4- or 16-byte address and its TTL.
type allowlistRecord struct {
	address []byte
	ttl     uint32
}

type appAllowlist struct {
	mu sync.RWMutex
	// configured records whether the last SetAppAllowlist carried any UID. It is the Go-side
	// "hasAppAllowlistUIDs" answer, kept here so a config of only invalid UIDs does not enable
	// strict mode.
	configured bool
	// selected is the set of UIDs the last config put under strict mode. It is immutable after
	// publication and only used by the no-kernel fail-closed path.
	selected map[int]struct{}
	// clock is only overridden by tests; nil means time.Now.
	clock func() time.Time
	// probed keeps the dlopen failure from being logged on every config push.
	probed bool
	kernel *nativeAllowlist
}

func (e *Engine) SetAppAllowlist(rulesJSON string) {
	entries := parseAppAllowlistRules(rulesJSON)

	a := &e.appAllowlist
	// Hold the write lock across configure so readers see either the old rules or the new ones,
	// never a new kernel state paired with the old `configured` flag.
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.kernel == nil && !a.probed {
		a.probed = true
		if kernel, err := newNativeAllowlist(); err == nil {
			a.kernel = kernel
		}
	}
	if a.kernel != nil {
		if err := a.kernel.configure(entries); err != nil {
			logf("[AppAllowlist] configure failed: %v", err)
		}
	}
	selected := make(map[int]struct{}, len(entries))
	for _, entry := range entries {
		selected[entry.uid] = struct{}{}
	}
	a.selected = selected
	a.configured = len(entries) > 0
}

// parseAppAllowlistRules keeps the JSON/`strconv` side of the old SetAppAllowlist. Normalization
// (trim, Unicode lowercase, one trailing dot) happens in the kernel so config and query walks can
// never disagree.
func parseAppAllowlistRules(rulesJSON string) []appAllowlistEntry {
	if strings.TrimSpace(rulesJSON) == "" {
		return nil
	}
	var raw map[string][]string
	if err := json.Unmarshal([]byte(rulesJSON), &raw); err != nil {
		return nil
	}

	// The old code assigned `rules[uid] = domMap` while ranging a map, so a duplicate UID's "last
	// write" was nondeterministic. Collecting into a map keeps the same final set, and sorting the
	// result only makes the payload deterministic.
	merged := make(map[int][]string, len(raw))
	for uidStr, domains := range raw {
		uid, err := strconv.Atoi(strings.TrimSpace(uidStr))
		if err != nil || uid <= 0 {
			continue
		}
		merged[uid] = domains
	}
	if len(merged) == 0 {
		return nil
	}

	uids := make([]int, 0, len(merged))
	for uid := range merged {
		uids = append(uids, uid)
	}
	sort.Ints(uids)
	entries := make([]appAllowlistEntry, 0, len(uids))
	for _, uid := range uids {
		entries = append(entries, appAllowlistEntry{uid: uid, domains: merged[uid]})
	}
	return entries
}

// snapshot returns the current config state, kernel and clock in one lock acquisition. The
// `selected` map is never mutated after publication, so the reference stays valid after unlock.
func (a *appAllowlist) snapshot() (bool, map[int]struct{}, *nativeAllowlist, func() time.Time) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.configured, a.selected, a.kernel, a.clock
}

func uidSelected(selected map[int]struct{}, uid int) bool {
	_, ok := selected[uid]
	return ok
}

func (a *appAllowlist) currentTime(clock func() time.Time) time.Time {
	if clock != nil {
		return clock()
	}
	return time.Now()
}

func (e *Engine) appAllowlistDomainAllowed(uid int, domain string) bool {
	configured, selected, kernel, _ := e.appAllowlist.snapshot()
	if !configured {
		return true
	}
	if kernel == nil {
		// Fail closed only for the selected UIDs; other apps keep their old, unrestricted path.
		return !uidSelected(selected, uid)
	}
	return kernel.domainAllowed(uid, domain)
}

func (e *Engine) appAllowlistConnectionAllowed(uid int, ip net.IP) bool {
	if ip.IsLoopback() {
		return true
	}
	configured, selected, kernel, clock := e.appAllowlist.snapshot()
	if !configured {
		return true
	}
	if kernel == nil {
		return !uidSelected(selected, uid)
	}
	return kernel.connectionAllowed(uid, ip, e.appAllowlist.currentTime(clock))
}

// hasAppAllowlistUIDs reports whether any UID is under strict allowlist mode.
// Used to keep the cache-hit hot path free of an extra DNS unpack.
func (e *Engine) hasAppAllowlistUIDs() bool {
	if e == nil {
		return false
	}
	configured, _, _, _ := e.appAllowlist.snapshot()
	return configured
}

// grantCount exposes the kernel's stored grants for a UID (the old test read len(ips[uid])).
func (a *appAllowlist) grantCount(uid int) int {
	_, _, kernel, _ := a.snapshot()
	if kernel == nil {
		return 0
	}
	return kernel.grantCount(uid)
}

// rememberAppAllowlistWire grants app-allowlist IP authorization from an already serialized
// DNS response (one served straight from the DNS cache).
//
// Upstream paths grant authorization via rememberAppAllowlistResponse on the resolved
// *dns.Msg, but the cache-hit and stale-while-revalidate branches return wire bytes and used
// to return early. A whitelisted app then resolved from cache and had every following
// connection refused by appAllowlistConnectionAllowed, so "解析成功、连接恒被拦" was permanent
// while the cache kept answering.
//
// The grant covers exactly the answer handed to the client, so its lifetime never exceeds the
// TTL the client was told.
func (e *Engine) rememberAppAllowlistWire(uid int, rawResponse []byte) {
	if e == nil || len(rawResponse) < 12 {
		return
	}
	if !e.hasAppAllowlistUIDs() {
		return
	}
	var msg dns.Msg
	if err := msg.Unpack(rawResponse); err != nil {
		return
	}
	e.rememberAppAllowlistResponse(uid, &msg)
}

func (e *Engine) rememberAppAllowlistResponse(uid int, response *dns.Msg) {
	if response == nil || len(response.Answer) == 0 {
		return
	}
	configured, _, kernel, clock := e.appAllowlist.snapshot()
	if !configured || kernel == nil {
		return
	}

	questionName := ""
	if len(response.Question) > 0 {
		// Raw; the kernel applies the same trim-one-dot + Unicode-lowercase rule as the config.
		questionName = response.Question[0].Name
	}

	records := make([]allowlistRecord, 0, len(response.Answer))
	for _, answer := range response.Answer {
		switch rr := answer.(type) {
		case *dns.A:
			if v4 := rr.A.To4(); v4 != nil {
				records = append(records, allowlistRecord{address: append([]byte(nil), v4...), ttl: rr.Hdr.Ttl})
			}
		case *dns.AAAA:
			if v6 := rr.AAAA.To16(); v6 != nil {
				records = append(records, allowlistRecord{address: append([]byte(nil), v6...), ttl: rr.Hdr.Ttl})
			}
		}
	}
	if len(records) == 0 {
		return
	}
	if err := kernel.remember(uid, questionName, records, e.appAllowlist.currentTime(clock)); err != nil {
		logf("[AppAllowlist] remember failed: %v", err)
	}
}
