package tunnel

import (
	"fmt"
	"sync"
)

// ─────────────────────────────────────────────────────────────────────────────
// conn_log.go — full-tunnel per-app attribution + connection logging.
//
// In full-tunnel mode the stack sees every flow's 5-tuple and (via the UID
// resolver) the owning UID. This lets us:
//   • attribute DNS queries to the real app (the legacy ServeDNS path only
//     knew "RootProxy" in VPN mode), and
//   • surface actual connections (TCP/UDP) — the only way to see apps like
//     Telegram / WhatsApp that connect to hard-coded IPs and barely use DNS,
//     so nothing shows in a DNS-only log.
//
// UID→package uses AppUidResolver (int arg only) — NOT AppResolver, whose
// []byte args panic under Go's cgocheck when called from this concurrent
// hot path.
// ─────────────────────────────────────────────────────────────────────────────

// appNameForFlow resolves the package name of the app owning a flow, or ""
// if it can't be determined. Cheap-ish: one UID lookup + one UID→package
// lookup (both int-only JNI calls).
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

// connLogSeen dedups connection-log entries by (uid-less) app+dest tuple so a
// page opening many flows to the same server doesn't flood the log. Cleared
// on engine stop (a fresh Engine per VPN session).
var connLogSeen sync.Map // key string -> struct{}

// logConnection reports a connection to the DNS-log callback so it shows in
// the app's log screen (marked blockedBy="connection"). Deduped per
// app+destIP+destPort. protocol is ProtocolTCP/ProtocolUDP. Best-effort and
// non-blocking-friendly; skips silently if no log callback / no resolver.
func (e *Engine) logConnection(flow flowID, protocol int) {
	cb := e.logCallback
	if cb == nil {
		return
	}
	// Resolve owning app. Always log the connection even if the app can't
	// be resolved (fall back to uid:<n> / unknown) so no traffic is silently
	// hidden — the whole point is visibility into what each app connects to.
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
	// Reuse the DNS-log pipeline: domain = "proto dest:port", resolvedIP =
	// dest, appName = package (Kotlin maps it to a friendly label),
	// blockedBy = "connection" so the UI can distinguish it from DNS.
	cb.OnDNSQuery(
		fmt.Sprintf("%s %s:%d", proto, dest, flow.serverPort),
		false, 0, 0, app, dest, "connection", "",
	)
}
