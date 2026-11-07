// dns_blocks.go owns the dynamic block escalation handle.
//
// The per-domain request counter, its window, the NXDOMAIN hold and the NODATA answer for
// everything below the threshold live in rust/diting-dns-core (src/block.rs). What stays here is
// the handle lifecycle, the `dynamicBlockConfig` -> nanoseconds conversion and the fallback used
// when the kernel is absent: blocks then keep the configured response mode, which is what a
// disabled escalation already did.
//
// The kernel never reads a clock: each call passes time.Now() as unix nanoseconds, so a scripted
// sequence replays exactly (rust/diting-dns-core/tests/corpus.rs).

package tunnel

import (
	"runtime"
	"time"
)

// dynamicBlockTracker owns one kernel handle: the escalation state of one engine.
type dynamicBlockTracker struct {
	native *nativeDynamicBlocks
}

func newDynamicBlockTracker() *dynamicBlockTracker {
	tracker := &dynamicBlockTracker{}
	handle, err := newNativeDynamicBlocks()
	if err != nil {
		// The loader logged the reason once per process; escalation stays off.
		return tracker
	}
	tracker.native = handle
	// The handle is released with the tracker: no caller can hold the pointer after the engine is
	// gone, so no goroutine can touch a freed handle.
	runtime.SetFinalizer(tracker, func(t *dynamicBlockTracker) {
		if t.native != nil {
			t.native.free()
			t.native = nil
		}
	})
	return tracker
}

// reset forgets every domain counter; ApplyDNSConfig calls it after publishing a new snapshot.
func (t *dynamicBlockTracker) reset() {
	if t == nil || t.native == nil {
		return
	}
	t.native.reset()
}

// responseFor resolves the block response mode for one blocked query. `domain` is already
// normalized by effectiveBlockResponseType (trimmed, lowercased, trailing dot removed).
func (t *dynamicBlockTracker) responseFor(domain string, cfg dynamicBlockConfig, fallback ResponseType) ResponseType {
	if t == nil || t.native == nil {
		return fallback
	}
	// A negative threshold cannot happen through ApplyDNSConfig (it normalizes to >= 1); clamping
	// to 0 keeps the old `requestCount > threshold` verdict for a direct writer instead of
	// wrapping around to "never escalate".
	threshold := uint32(0)
	if cfg.RequestThreshold > 0 {
		threshold = uint32(cfg.RequestThreshold)
	}
	return t.native.response(
		domain,
		cfg.Enabled,
		threshold,
		int64(cfg.WindowSeconds)*int64(time.Second),
		int64(cfg.NXDomainSeconds)*int64(time.Second),
		uint32(fallback),
		time.Now().UnixNano(),
	)
}
