// engine_connection_log.go provides full-tunnel per-app traffic attribution and connection logging.
//
// Key Mechanisms:
// - Flow Attribution: In full-tunnel mode, the stack extracts the 5-tuple and queries the UID resolver
//   to identify the owning Android package, capturing apps connecting directly to hard-coded IPs (e.g. WhatsApp, Telegram).
// - JNI Memory Safety: UID-to-package resolution uses AppUidResolver (taking int arguments only) rather than
//   AppResolver to prevent Go runtime cgocheck panics under concurrent hot-path execution.
// - Deduplication & UI Pipeline: connLogSeen (sync.Map) deduplicates entries by app+dest tuple to avoid log flooding,
//   and events are dispatched through notifyLog tagged as "connection" or "firewall:<reason>".

package tunnel

import (
	"fmt"
	"sync"
)

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

var connLogSeen sync.Map

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
	key := fmt.Sprintf("%s|%s|%d|%d", app, dest, flow.serverPort, protocol)
	if _, dup := connLogSeen.LoadOrStore(key, struct{}{}); dup {
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
	key := fmt.Sprintf("blk|%s|%s|%d|%d|%s", app, dest, flow.serverPort, protocol, reason)
	if _, dup := connLogSeen.LoadOrStore(key, struct{}{}); dup {
		return
	}
	e.notifyLog(
		fmt.Sprintf("%s %s:%d", proto, dest, flow.serverPort),
		true, 0, 0, app, dest, "firewall:"+reason, "", false,
	)
}
