package tunnel

import (
	"bufio"
	"fmt"
	"os"
	"path"
	"strconv"
	"strings"
	"sync"
	"time"
)

// MITM Smart Filter — dynamic interception decisions.
//
// Multi-layer decision engine (checked in order):
//   1. UID check        → only allowed UIDs (browsers) are candidates for MITM.
//   2. Auto-blacklist   → domains with failed TLS handshake (cert pinning) or EV/mTLS, with 7-day TTL and failure threshold.
//   3. Bypass patterns  → runtime-loaded bypass patterns with wildcard support (*).
//   4. Refined keywords → domains with sensitive tokens (bank, pay, auth, etc.) using label/word-boundary matching.
//   5. IP addresses     → direct IP access is never intercepted.
//
// All checks pass → intercept (MITM + cosmetic CSS injection).
// Default for non-browser UIDs → direct pass-through.

const defaultBlacklistTTL = 7 * 24 * time.Hour

type blacklistEntry struct {
	addedAt   time.Time
	expiresAt time.Time
	reason    string
}

type failureRecord struct {
	count    int
	lastSeen time.Time
}

// MitmFilter manages dynamic interception decisions.
type MitmFilter struct {
	mu sync.RWMutex

	// allowedUIDs contains the UIDs of apps we're allowed to MITM (browsers).
	// Key = UID (int32), stored as int for map efficiency.
	allowedUIDs map[int]bool

	// blacklist contains domains where TLS handshake failed or EV/mTLS detected.
	// Has expiration timestamp (TTL) and reason.
	blacklist map[string]blacklistEntry

	// failureCounts tracks recent TLS handshake failures for threshold checking before blacklisting.
	failureCounts map[string]failureRecord

	// httpsBypassPatterns contains runtime-loaded HTTPS bypass rules (exact, suffix, or glob wildcard).
	httpsBypassPatterns []string

	// blacklistPath, when non-empty, is the file the auto-blacklist is persisted to.
	blacklistPath   string
	blacklistFileMu sync.Mutex
}

// sniSensitiveKeywords — sensitive tokens. Catches banking, authentication,
// and payment services using word-boundary and label-level checks.
var sniSensitiveKeywords = []string{
	"bank",
	"pay",
	"payment",
	"auth",
	"oauth",
	"login",
	"signin",
	"token",
	"secure",
	"wallet",
	"crypto",
	"trading",
	"invest",
	"finance",
	"insurance",
	"healthcare",
	"medical",
	"gov",
}

// NewMitmFilter creates a new filter with no allowed UIDs.
func NewMitmFilter() *MitmFilter {
	return &MitmFilter{
		allowedUIDs:         make(map[int]bool),
		blacklist:           make(map[string]blacklistEntry),
		failureCounts:       make(map[string]failureRecord),
		httpsBypassPatterns: make([]string, 0),
	}
}

// SetAllowedUIDs replaces the set of UIDs allowed for MITM interception.
func (f *MitmFilter) SetAllowedUIDs(uids []int) {
	f.mu.Lock()
	defer f.mu.Unlock()

	f.allowedUIDs = make(map[int]bool, len(uids))
	for _, uid := range uids {
		f.allowedUIDs[uid] = true
	}
	logf("MITM Filter: updated allowed UIDs (%d apps)", len(uids))
}

// IsUIDAllowed checks if a UID is in the allowed set.
func (f *MitmFilter) IsUIDAllowed(uid int) bool {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.allowedUIDs[uid]
}

// HasAllowedUIDs returns true if any browser UIDs have been configured.
func (f *MitmFilter) HasAllowedUIDs() bool {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return len(f.allowedUIDs) > 0
}

// SetHttpsBypassRules sets the dedicated HTTPS bypass rules (supports exact domain, suffix, and glob wildcard *).
func (f *MitmFilter) SetHttpsBypassRules(rules []string) {
	clean := make([]string, 0, len(rules))
	for _, s := range rules {
		s = strings.TrimSpace(strings.ToLower(s))
		if s == "" || s[0] == '#' || strings.HasPrefix(s, "//") {
			continue
		}
		clean = append(clean, s)
	}
	f.mu.Lock()
	f.httpsBypassPatterns = clean
	f.mu.Unlock()
	logf("MITM Filter: loaded %d HTTPS bypass rules", len(clean))
}

// SetExtraPassthroughSuffixes provides backward compatibility for callers.
func (f *MitmFilter) SetExtraPassthroughSuffixes(suffixes []string) {
	f.SetHttpsBypassRules(suffixes)
}

// matchHostPattern evaluates host against pattern supporting:
// - Exact match ("example.com")
// - Subdomain suffix (".example.com" or "example.com" matching "*.example.com")
// - Wildcard glob ("*.example.com", "*-cdn.google.com", "api.*.test.com")
// - AdGuard format ("||example.com^", "@@||example.com^")
func matchHostPattern(pattern, host string) bool {
	pattern = strings.ToLower(strings.TrimSpace(pattern))
	host = strings.ToLower(strings.TrimSpace(host))
	if pattern == "" || host == "" {
		return false
	}

	// Clean AdGuard modifiers
	pattern = strings.TrimPrefix(pattern, "@@")
	pattern = strings.TrimPrefix(pattern, "||")
	pattern = strings.TrimRight(pattern, "^")

	if !strings.Contains(pattern, "*") {
		clean := strings.TrimPrefix(pattern, ".")
		if host == clean || strings.HasSuffix(host, "."+clean) {
			return true
		}
		return false
	}

	// Wildcard matching
	if strings.HasPrefix(pattern, "*.") && host == pattern[2:] {
		return true
	}
	matched, err := path.Match(pattern, host)
	return err == nil && matched
}

// isSensitiveHost checks whether the hostname contains sensitive banking, authentication,
// or payment terms using label and word-boundary matching to prevent false positives like
// "author.com", "company.com", or "investor.com".
func isSensitiveHost(host string) bool {
	labels := strings.Split(host, ".")
	for _, lbl := range labels {
		if lbl == "" {
			continue
		}

		// 1. Direct label match against sensitive keywords
		for _, kw := range sniSensitiveKeywords {
			if lbl == kw {
				return true
			}
		}

		// 2. Tokenize label by hyphens/underscores (e.g. "auth-api", "my_login")
		tokens := strings.FieldsFunc(lbl, func(r rune) bool {
			return r == '-' || r == '_'
		})
		for _, tok := range tokens {
			for _, kw := range sniSensitiveKeywords {
				if tok == kw {
					return true
				}
			}
		}

		// 3. Known banking / payment brand & compound patterns
		if strings.HasSuffix(lbl, "bank") && len(lbl) >= 6 {
			return true // e.g. citibank, chasebank, mybank
		}
		if strings.HasPrefix(lbl, "bank") && len(lbl) >= 6 {
			return true // e.g. bankofamerica
		}
		switch lbl {
		case "paypal", "alipay", "tenpay", "wechatpay", "unionpay", "applepay", "googlepay":
			return true
		}
		if strings.Contains(lbl, "alipay") || strings.Contains(lbl, "paypal") || strings.Contains(lbl, "wechatpay") {
			return true
		}
	}
	return false
}

// IsInterceptionAllowed determines if a domain should be MITM'd.
// Returns true  → Intercept (decrypt TLS).
// Returns false → Forward directly (no decryption).
func (f *MitmFilter) IsInterceptionAllowed(host string) bool {
	host = strings.ToLower(strings.TrimSpace(host))

	if idx := strings.LastIndex(host, ":"); idx != -1 {
		host = host[:idx]
	}

	now := time.Now()

	// Layer 1: Check auto-blacklist (with TTL)
	f.mu.RLock()
	entry, blacklisted := f.blacklist[host]
	f.mu.RUnlock()
	if blacklisted {
		if now.Before(entry.expiresAt) {
			return false
		}
		// Lazy eviction of expired entry
		f.mu.Lock()
		delete(f.blacklist, host)
		f.mu.Unlock()
	}

	// Layer 2: Check runtime-loaded HTTPS bypass patterns (exact, suffix, and wildcard)
	f.mu.RLock()
	bypassPatterns := f.httpsBypassPatterns
	f.mu.RUnlock()
	for _, pattern := range bypassPatterns {
		if matchHostPattern(pattern, host) {
			return false
		}
	}

	// Layer 3: Refined SNI sensitive keyword scan (word-boundary & label-based)
	if isSensitiveHost(host) {
		return false
	}

	// Layer 4: IP addresses → never intercept
	if isIPAddress(host) {
		return false
	}

	return true
}

// RecordFailure tracks TLS handshake failures and adds to blacklist once the failure threshold is reached.
// Returns true if the host was added to the blacklist.
func (f *MitmFilter) RecordFailure(host string, err error) bool {
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" || err == nil {
		return false
	}
	errStr := strings.ToLower(err.Error())

	threshold := 3
	reason := "handshake_failure"
	if strings.Contains(errStr, "unknown certificate") ||
		strings.Contains(errStr, "certificate unknown") ||
		strings.Contains(errStr, "bad certificate") {
		threshold = 2
		reason = "cert_rejected"
	}

	now := time.Now()
	f.mu.Lock()
	rec, exists := f.failureCounts[host]
	if !exists || now.Sub(rec.lastSeen) > 10*time.Minute {
		rec = failureRecord{count: 1, lastSeen: now}
	} else {
		rec.count++
		rec.lastSeen = now
	}
	f.failureCounts[host] = rec
	count := rec.count
	f.mu.Unlock()

	if count >= threshold {
		f.BlacklistDomainWithReason(host, fmt.Sprintf("%s (%d failures)", reason, count))
		return true
	}
	logf("MITM Filter: recorded TLS failure for '%s' (%d/%d): %v", host, count, threshold, err)
	return false
}

// BlacklistDomain permanently adds a domain to the passthrough cache with default reason.
func (f *MitmFilter) BlacklistDomain(host string) {
	f.BlacklistDomainWithReason(host, "pinning")
}

// BlacklistDomainWithReason adds a domain to the passthrough cache with 7-day TTL and persists it.
func (f *MitmFilter) BlacklistDomainWithReason(host, reason string) {
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" {
		return
	}

	now := time.Now()
	expiresAt := now.Add(defaultBlacklistTTL)

	f.mu.Lock()
	entry, alreadyKnown := f.blacklist[host]
	if alreadyKnown && now.Before(entry.expiresAt) {
		f.mu.Unlock()
		return
	}
	f.blacklist[host] = blacklistEntry{
		addedAt:   now,
		expiresAt: expiresAt,
		reason:    reason,
	}
	path := f.blacklistPath
	f.mu.Unlock()

	logf("MITM Filter: auto-blacklisted '%s' (%s, TTL=%v)", host, reason, defaultBlacklistTTL)

	if path != "" {
		f.appendBlacklistLine(path, host, expiresAt, reason)
	}
}

// ClearBlacklist clears in-memory and persistent auto-blacklist entries.
func (f *MitmFilter) ClearBlacklist() {
	f.mu.Lock()
	f.blacklist = make(map[string]blacklistEntry)
	f.failureCounts = make(map[string]failureRecord)
	path := f.blacklistPath
	f.mu.Unlock()

	if path != "" {
		f.blacklistFileMu.Lock()
		_ = os.WriteFile(path, []byte(""), 0644)
		f.blacklistFileMu.Unlock()
	}
	logf("MITM Filter: cleared auto-blacklist")
}

// RemoveFromBlacklist removes a specific domain from the blacklist.
func (f *MitmFilter) RemoveFromBlacklist(host string) {
	host = strings.ToLower(strings.TrimSpace(host))
	f.mu.Lock()
	delete(f.blacklist, host)
	delete(f.failureCounts, host)
	f.mu.Unlock()
}

// LoadPersistentBlacklist loads existing auto-blacklisted entries from disk.
func (f *MitmFilter) LoadPersistentBlacklist(path string) {
	now := time.Now()
	loaded := 0
	if file, err := os.Open(path); err == nil {
		sc := bufio.NewScanner(file)
		f.mu.Lock()
		for sc.Scan() {
			line := strings.ToLower(strings.TrimSpace(sc.Text()))
			if line == "" || line[0] == '#' {
				continue
			}
			parts := strings.Split(line, "|")
			host := strings.TrimSpace(parts[0])
			if host == "" {
				continue
			}
			expiresAt := now.Add(defaultBlacklistTTL)
			reason := "pinning"
			if len(parts) >= 2 {
				if expUnix, err := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64); err == nil {
					expTime := time.Unix(expUnix, 0)
					if now.After(expTime) {
						continue // expired entry skipped
					}
					expiresAt = expTime
				}
			}
			if len(parts) >= 3 {
				reason = strings.TrimSpace(parts[2])
			}
			f.blacklist[host] = blacklistEntry{
				addedAt:   now,
				expiresAt: expiresAt,
				reason:    reason,
			}
			loaded++
		}
		f.mu.Unlock()
		file.Close()
	}

	f.mu.Lock()
	f.blacklistPath = path
	f.mu.Unlock()
	logf("MITM Filter: persistent blacklist at %s (%d active entries loaded)", path, loaded)
}

// appendBlacklistLine appends one domain with TTL to the persistent blacklist file.
func (f *MitmFilter) appendBlacklistLine(path, host string, expiresAt time.Time, reason string) {
	f.blacklistFileMu.Lock()
	defer f.blacklistFileMu.Unlock()

	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		logf("MITM Filter: WARNING — cannot persist blacklist entry '%s': %v", host, err)
		return
	}
	defer file.Close()
	line := fmt.Sprintf("%s|%d|%s\n", host, expiresAt.Unix(), reason)
	if _, err := file.WriteString(line); err != nil {
		logf("MITM Filter: WARNING — failed writing blacklist entry '%s': %v", host, err)
	}
}

// GetBlacklistCount returns the number of active (non-expired) auto-blacklisted domains.
func (f *MitmFilter) GetBlacklistCount() int {
	now := time.Now()
	f.mu.RLock()
	defer f.mu.RUnlock()
	count := 0
	for _, entry := range f.blacklist {
		if now.Before(entry.expiresAt) {
			count++
		}
	}
	return count
}

// isIPAddress checks if a string looks like an IP address (v4 or v6).
func isIPAddress(host string) bool {
	if strings.Contains(host, ":") {
		return true
	}
	for _, c := range host {
		if c != '.' && (c < '0' || c > '9') {
			return false
		}
	}
	return len(host) > 0
}
