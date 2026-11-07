//go:build cgo

// connlog_seen_test.go pins the bounded connection-log dedupe set. The state moved into the Rust
// kernel, so the test needs the library; the Go side keeps only the handle and the disabled
// fallback.

package tunnel

import (
	"strconv"
	"testing"
)

// The kernel's MAX_ENTRIES; kept here so the assertion does not need a second symbol.
const connLogSeenMaxEntries = 8192

// A-073: the set must never grow past its bound, and the overflow reset must fire.
func TestConnLogSeenDedupIsBounded(t *testing.T) {
	var dedup connLogSeenDedup
	dedup.reset()

	if dedup.markSeen("", "app", "k1", 1, 6, "") {
		t.Fatalf("first sighting reported as duplicate")
	}
	if !dedup.markSeen("", "app", "k1", 1, 6, "") {
		t.Fatalf("second sighting not reported as duplicate")
	}

	for i := 0; i < connLogSeenMaxEntries+50; i++ {
		dedup.markSeen("", "app", strconv.Itoa(i), 1, 6, "")
	}
	if got := dedup.size(); got > connLogSeenMaxEntries {
		t.Fatalf("dedupe set grew past the bound: %d", got)
	}
	if dedup.clearedCount() == 0 {
		t.Fatalf("overflow reset never fired")
	}

	dedup.reset()
	if dedup.size() != 0 {
		t.Fatalf("reset left %d entries", dedup.size())
	}
}

// The blocked prefix and the reason are part of the key; a normal connection and a blocked one to
// the same destination must both be logged.
func TestConnLogSeenKeyIncludesPrefixAndReason(t *testing.T) {
	var dedup connLogSeenDedup
	dedup.reset()

	if dedup.markSeen("", "app", "203.0.113.7", 443, 6, "") {
		t.Fatal("normal connection reported as duplicate")
	}
	if dedup.markSeen("blk|", "app", "203.0.113.7", 443, 6, "uid_blocked") {
		t.Fatal("blocked connection must use a different key")
	}
	if !dedup.markSeen("blk|", "app", "203.0.113.7", 443, 6, "uid_blocked") {
		t.Fatal("repeated blocked connection not reported as duplicate")
	}
	if dedup.markSeen("blk|", "app", "203.0.113.7", 443, 6, "quic_forced_tcp") {
		t.Fatal("a different reason must use a different key")
	}
}
