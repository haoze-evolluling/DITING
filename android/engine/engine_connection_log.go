// engine_connection_log.go provides full-tunnel per-app traffic attribution and connection logging.
//
// Key Mechanisms:
// - Flow Attribution: In full-tunnel mode, the stack extracts the 5-tuple and queries the UID resolver
//   to identify the owning Android package, capturing apps connecting directly to hard-coded IPs (e.g. WhatsApp, Telegram).
// - JNI Memory Safety: UID-to-package resolution uses AppUidResolver (taking int arguments only) rather than
//   AppResolver to prevent Go runtime cgocheck panics under concurrent hot-path execution.
// - Deduplication & UI Pipeline: the Rust connlog kernel deduplicates entries by app+dest tuple to
//   avoid log flooding, and events are dispatched through notifyLog tagged as "connection" or
//   "firewall:<reason>". The kernel also builds the key, so Go no longer allocates it for every
//   flow. Without the library deduplication is disabled (every line is emitted, only more noisy).

package tunnel

import (
	"fmt"
	"sync"
)

// connLogSeenDedup owns the Rust dedupe handle for the current session. The kernel drops the
// entries on an overflow reset rather than evicting individually: the keys are cheap to rebuild
// and a stale key only costs one duplicate log line.
type connLogSeenDedup struct {
	mu     sync.Mutex
	probed bool
	kernel *nativeConnLog
}

var connLogSeen connLogSeenDedup

func (d *connLogSeenDedup) ensureKernel() *nativeConnLog {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.kernel != nil {
		return d.kernel
	}
	if d.probed {
		return nil
	}
	d.probed = true
	if kernel, err := newNativeConnLog(); err == nil {
		d.kernel = kernel
	}
	return d.kernel
}

// markSeen builds "[blk|]app|dest|port|proto[|reason]" in the kernel and reports whether it was
// already present. When the set is full the kernel empties it first, trading exactness for a
// bounded footprint. Without the kernel every key looks new, so nothing is suppressed.
func (d *connLogSeenDedup) markSeen(prefix, app, dest string, port, protocol int, reason string) (dup bool) {
	kernel := d.ensureKernel()
	if kernel == nil {
		return false
	}
	return kernel.mark(prefix, app, dest, port, protocol, reason)
}

// reset empties the set; called when a full-tunnel session starts. The kernel keeps its overflow
// counter across this, exactly like the old Go `cleared` field.
func (d *connLogSeenDedup) reset() {
	kernel := d.ensureKernel()
	if kernel == nil {
		return
	}
	kernel.reset()
}

// size reports the current entry count (test/telemetry helper).
func (d *connLogSeenDedup) size() int {
	kernel := d.ensureKernel()
	if kernel == nil {
		return 0
	}
	return kernel.size()
}

// clearedCount reports how many overflow resets happened (the old `cleared` atomic).
func (d *connLogSeenDedup) clearedCount() uint64 {
	kernel := d.ensureKernel()
	if kernel == nil {
		return 0
	}
	return kernel.cleared()
}

func (e *Engine) appNameForFlow(flow flowID, protocol int) string {
	uidr := e.uidResolver
	r := e.appUidResolver
	if uidr == nil || r == nil {
		return ""
	}
	uid := resolveFlowUID(uidr, protocol, flow)
	if uid == UIDUnknown {
		return ""
	}
	return r.PackageForUid(uid)
}

func (e *Engine) logConnection(flow flowID, protocol int) {
	hasBatch := e.logAggregator != nil && e.logAggregator.hasCallback()
	if !hasBatch && e.logCallback == nil {
		return
	}

	uid := UIDUnknown
	if e.uidResolver != nil {
		uid = resolveFlowUID(e.uidResolver, protocol, flow)
	}
	app := ""
	if uid != UIDUnknown && e.appUidResolver != nil {
		app = e.appUidResolver.PackageForUid(uid)
	}
	if app == "" {
		if uid != UIDUnknown {
			app = fmt.Sprintf("uid:%d", uid)
		} else {
			app = "unknown"
		}
	}
	dest := flow.serverIP.String()
	if connLogSeen.markSeen("", app, dest, flow.serverPort, protocol, "") {
		return
	}
	proto := "TCP"
	if protocol == ProtocolUDP {
		proto = "UDP"
	}

	e.notifyLog(
		fmt.Sprintf("%s %s:%d", proto, dest, flow.serverPort),
		false, 0, 0, app, dest, "connection", "", false,
	)
}

func (e *Engine) logBlockedConnection(flow flowID, protocol int, reason string) {
	if e == nil {
		return
	}
	hasBatch := e.logAggregator != nil && e.logAggregator.hasCallback()
	if !hasBatch && e.logCallback == nil {
		return
	}
	uid := UIDUnknown
	if e.uidResolver != nil {
		uid = resolveFlowUID(e.uidResolver, protocol, flow)
	}
	app := ""
	if uid != UIDUnknown && e.appUidResolver != nil {
		app = e.appUidResolver.PackageForUid(uid)
	}
	if app == "" {
		if uid != UIDUnknown {
			app = fmt.Sprintf("uid:%d", uid)
		} else {
			app = "unknown"
		}
	}
	dest := flow.serverIP.String()
	proto := "TCP"
	if protocol == ProtocolUDP {
		proto = "UDP"
	}
	if connLogSeen.markSeen("blk|", app, dest, flow.serverPort, protocol, reason) {
		return
	}
	e.notifyLog(
		fmt.Sprintf("%s %s:%d", proto, dest, flow.serverPort),
		true, 0, 0, app, dest, "firewall:"+reason, "", false,
	)
}
