// mitm_filter.go implements the multi-layer Smart Filter governing MITM interception decisions.
//
// Evaluation Sequence (Checked in Order):
// 1. UID Check: Restricts MITM interception strictly to user-whitelisted applications (e.g., specific browsers).
// 2. Auto-Blacklist: Automatically bypasses domains that failed prior TLS handshakes (certificate pinning or mTLS).
// 3. Bypass Patterns: Evaluates dynamic wildcard and prefix exclusion rules.
// 4. Sensitive Keywords: Bypasses financial, banking, and authentication endpoints (e.g., bank, pay, auth, login).
// 5. IP Destinations: Direct IP connections bypass interception.
// All gates pass -> Intercept (TLS decryption + cosmetic CSS injection).

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

type MitmFilter struct {
	mu sync.RWMutex

	allowedUIDs map[int]bool

	blacklist map[string]blacklistEntry

	failureCounts map[string]failureRecord

	httpsBypassPatterns []string

	blacklistPath   string
	blacklistFileMu sync.Mutex
}

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

func NewMitmFilter() *MitmFilter {
	return &MitmFilter{
		allowedUIDs:         make(map[int]bool),
		blacklist:           make(map[string]blacklistEntry),
		failureCounts:       make(map[string]failureRecord),
		httpsBypassPatterns: make([]string, 0),
	}
}

func (f *MitmFilter) SetAllowedUIDs(uids []int) {
	f.mu.Lock()
	defer f.mu.Unlock()

	f.allowedUIDs = make(map[int]bool, len(uids))
	for _, uid := range uids {
		f.allowedUIDs[uid] = true
	}
	logf("MITM Filter: updated allowed UIDs (%d apps)", len(uids))
}

func (f *MitmFilter) IsUIDAllowed(uid int) bool {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.allowedUIDs[uid]
}

func (f *MitmFilter) HasAllowedUIDs() bool {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return len(f.allowedUIDs) > 0
}

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

func (f *MitmFilter) SetExtraPassthroughSuffixes(suffixes []string) {
	f.SetHttpsBypassRules(suffixes)
}

func matchHostPattern(pattern, host string) bool {
	pattern = strings.ToLower(strings.TrimSpace(pattern))
	host = strings.ToLower(strings.TrimSpace(host))
	if pattern == "" || host == "" {
		return false
	}

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

	if strings.HasPrefix(pattern, "*.") && host == pattern[2:] {
		return true
	}
	matched, err := path.Match(pattern, host)
	return err == nil && matched
}

func isSensitiveHost(host string) bool {
	labels := strings.Split(host, ".")
	for _, lbl := range labels {
		if lbl == "" {
			continue
		}

		for _, kw := range sniSensitiveKeywords {
			if lbl == kw {
				return true
			}
		}

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

		if strings.HasSuffix(lbl, "bank") && len(lbl) >= 6 {
			return true
		}
		if strings.HasPrefix(lbl, "bank") && len(lbl) >= 6 {
			return true
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

func (f *MitmFilter) IsInterceptionAllowed(host string) bool {
	host = strings.ToLower(strings.TrimSpace(host))

	if idx := strings.LastIndex(host, ":"); idx != -1 {
		host = host[:idx]
	}

	now := time.Now()

	f.mu.RLock()
	entry, blacklisted := f.blacklist[host]
	f.mu.RUnlock()
	if blacklisted {
		if now.Before(entry.expiresAt) {
			return false
		}

		f.mu.Lock()
		delete(f.blacklist, host)
		f.mu.Unlock()
	}

	f.mu.RLock()
	bypassPatterns := f.httpsBypassPatterns
	f.mu.RUnlock()
	for _, pattern := range bypassPatterns {
		if matchHostPattern(pattern, host) {
			return false
		}
	}

	if isSensitiveHost(host) {
		return false
	}

	if isIPAddress(host) {
		return false
	}

	return true
}

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

func (f *MitmFilter) BlacklistDomain(host string) {
	f.BlacklistDomainWithReason(host, "pinning")
}

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

func (f *MitmFilter) RemoveFromBlacklist(host string) {
	host = strings.ToLower(strings.TrimSpace(host))
	f.mu.Lock()
	delete(f.blacklist, host)
	delete(f.failureCounts, host)
	f.mu.Unlock()
}

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
						continue
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
