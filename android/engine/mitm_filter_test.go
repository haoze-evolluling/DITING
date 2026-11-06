//go:build cgo

// mitm_filter_test.go drives the MITM filter through the Rust kernel the way the engine does: the
// allow list, the exclusion patterns, the sensitive-host heuristics, the failure streaks and the
// persistent blacklist. The decisions themselves are pinned in rust/diting-mitm-core/src/*/tests.rs;
// these tests prove the boundary carries them.

package tunnel

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func newTestMitmFilter(t *testing.T) *MitmFilter {
	t.Helper()
	filter, err := NewMitmFilter()
	if err != nil {
		t.Fatalf("NewMitmFilter: %v", err)
	}
	t.Cleanup(func() { filter.native.free() })
	return filter
}

func TestMitmAllowedUIDs(t *testing.T) {
	filter := newTestMitmFilter(t)
	if filter.HasAllowedUIDs() {
		t.Fatal("a fresh filter must not intercept any app")
	}
	if got := filter.SetAllowedUIDs("1001, 1002 ,1001"); got != 2 {
		t.Fatalf("SetAllowedUIDs count = %d, want 2", got)
	}
	if !filter.HasAllowedUIDs() {
		t.Fatal("HasAllowedUIDs = false after setting two UIDs")
	}
	for _, uid := range []int{1001, 1002} {
		if !filter.IsUIDAllowed(uid) {
			t.Fatalf("IsUIDAllowed(%d) = false", uid)
		}
	}
	if filter.IsUIDAllowed(1003) {
		t.Fatal("IsUIDAllowed(1003) = true")
	}

	// Only the digits of each element count, exactly like the Go parser this replaced.
	if got := filter.SetAllowedUIDs("1a2,0,-3"); got != 2 {
		t.Fatalf("SetAllowedUIDs count = %d, want 2", got)
	}
	if !filter.IsUIDAllowed(12) || !filter.IsUIDAllowed(3) {
		t.Fatal("the digit-only parsing changed")
	}
}

func TestMitmBypassRulesAndSensitiveHosts(t *testing.T) {
	filter := newTestMitmFilter(t)
	if got := filter.SetHttpsBypassRules("# comment\n// comment\n\n Example.COM \n*.blog.example\r\n"); got != 2 {
		t.Fatalf("SetHttpsBypassRules count = %d, want 2", got)
	}

	for _, host := range []string{"example.com", "www.example.com", "blog.example", "cdn.blog.example"} {
		if filter.IsInterceptionAllowed(host) {
			t.Fatalf("bypass rule did not exclude %q", host)
		}
	}
	for _, host := range []string{
		"bank.com",         // whole-label sensitive keyword
		"API.BANK.com:443", // lowercased, port stripped, `bank` is a label
		"secure-login.cn",  // keyword inside a token
		"alipay.com",       // payment brand
		"1.2.3.4",          // bare address
		"::1",              // IPv6 literal
	} {
		if filter.IsInterceptionAllowed(host) {
			t.Fatalf("sensitive host %q was going to be intercepted", host)
		}
	}
	for _, host := range []string{"example.org", "cdn.website.net"} {
		if !filter.IsInterceptionAllowed(host) {
			t.Fatalf("ordinary host %q is not intercepted", host)
		}
	}
}

func TestMitmFailureStreakBlacklists(t *testing.T) {
	filter := newTestMitmFilter(t)
	err := errors.New("remote error: tls: handshake failure")
	for attempt := 1; attempt <= 2; attempt++ {
		if filter.RecordFailure("streak.example", err) {
			t.Fatalf("attempt %d blacklisted too early", attempt)
		}
		if filter.GetBlacklistCount() != 0 {
			t.Fatalf("attempt %d left a blacklist entry", attempt)
		}
	}
	if !filter.RecordFailure("streak.example", err) {
		t.Fatal("the third failure did not blacklist")
	}
	// A further failure keeps reporting "blacklisted" without adding a second entry.
	if !filter.RecordFailure("streak.example", err) {
		t.Fatal("a failure past the threshold stopped reporting the blacklist")
	}
	if count := filter.GetBlacklistCount(); count != 1 {
		t.Fatalf("blacklist count = %d, want 1", count)
	}
	if filter.IsInterceptionAllowed("streak.example") {
		t.Fatal("a blacklisted host is still intercepted")
	}

	// A rejected certificate only needs two failures.
	if filter.RecordFailure("pinned.example", errors.New("tls: unknown certificate")) {
		t.Fatal("a single rejection blacklisted")
	}
	if !filter.RecordFailure("pinned.example", errors.New("tls: unknown certificate")) {
		t.Fatal("the second rejection did not blacklist")
	}
	if count := filter.GetBlacklistCount(); count != 2 {
		t.Fatalf("blacklist count = %d, want 2", count)
	}

	// A nil error is not a failure, and never reaches the kernel.
	if filter.RecordFailure("pinned.example", nil) {
		t.Fatal("a nil error blacklisted")
	}

	filter.RemoveFromBlacklist("pinned.example")
	if count := filter.GetBlacklistCount(); count != 1 {
		t.Fatalf("blacklist count after removal = %d, want 1", count)
	}
	if !filter.IsInterceptionAllowed("pinned.example") {
		t.Fatal("a removed host is still blacklisted")
	}

	filter.ClearBlacklist()
	if count := filter.GetBlacklistCount(); count != 0 {
		t.Fatalf("blacklist count after clear = %d, want 0", count)
	}
	if !filter.IsInterceptionAllowed("streak.example") {
		t.Fatal("a cleared host is still blacklisted")
	}
}

func TestMitmPersistentBlacklist(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mitm_blacklist.txt")

	filter := newTestMitmFilter(t)
	if loaded := filter.LoadPersistentBlacklist(path); loaded != 0 {
		t.Fatalf("loading a missing file reported %d entries", loaded)
	}
	filter.BlacklistDomain("pinned.example")
	if count := filter.GetBlacklistCount(); count != 1 {
		t.Fatalf("blacklist count = %d, want 1", count)
	}

	// The kernel wrote `host|unix_seconds|reason`.
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read the blacklist file: %v", err)
	}
	line := strings.TrimSpace(string(raw))
	parts := strings.Split(line, "|")
	if len(parts) != 3 {
		t.Fatalf("blacklist line = %q", line)
	}
	if parts[0] != "pinned.example" || parts[2] != "pinning" {
		t.Fatalf("blacklist line = %q", line)
	}
	// The entry is a week out, so the unix seconds sit in the future.
	expiry, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		t.Fatalf("blacklist expiry %q: %v", parts[1], err)
	}
	now := time.Now().Unix()
	if expiry <= now || expiry > now+8*24*60*60 {
		t.Fatalf("blacklist expiry %d is not about a week out (now %d)", expiry, now)
	}

	// A second filter reloads the line and keeps refusing interception.
	reloaded := newTestMitmFilter(t)
	if loaded := reloaded.LoadPersistentBlacklist(path); loaded != 1 {
		t.Fatalf("loaded %d entries, want 1", loaded)
	}
	if reloaded.IsInterceptionAllowed("pinned.example") {
		t.Fatal("a reloaded entry is not applied")
	}

	// Clearing truncates the file, so nothing comes back on the next start.
	reloaded.ClearBlacklist()
	raw, err = os.ReadFile(path)
	if err != nil {
		t.Fatalf("read the truncated file: %v", err)
	}
	if len(raw) != 0 {
		t.Fatalf("the file still holds %q", raw)
	}
}
