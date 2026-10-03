// engine_types.go defines core interfaces, callbacks, and data structures bridging
// the Go tunnel engine and the Android Kotlin layer via gomobile bind.
//
// JNI Safety & Callback Contracts:
// - AppUidResolver maps UID to Android package names using integer arguments only;
//   byte-slice arguments are forbidden in concurrent paths to prevent Go runtime cgocheck panics.
// - DomainChecker evaluates domain status returning "" (pass), "__ALLOW__" (whitelist override),
//   or the specific blocking reason string.
// - SocketProtector wraps Android VpnService.protect() to exempt outbound sockets from VPN routing loops.
// - Callback interfaces provide telemetry for DNS queries, batched logs, race events,
//   and privacy-sanitized HTTP metadata.

package tunnel

type LogCallback interface {
	OnDNSQuery(domain string, blocked bool, queryType int, responseTimeMs int64, appName string, resolvedIPs string, blockedBy string, errorMessage string, cached bool)
}

type BatchLogCallback interface {
	OnDNSQueryBatch(jsonLogs string)
}

type RaceLogCallback interface {
	OnRaceResult(
		queryName string,
		queryType int,
		strategy string,
		providerCount int,
		success bool,
		elapsedMs int64,
		selectedProviderID string,
		selectedElapsedMs int64,
		winnerProviderID string,
		winnerElapsedMs int64,
		fallbackUsed bool,
		fallbackSuccess bool,
		errorMessage string,
	)
}

type HttpLogCallback interface {
	OnHttpEvent(packageName string, authority string, protocol string, outcome string, matchedRule string)
}

type OutboundProxyStatusCallback interface {
	OnOutboundProxyStatus(state string, message string)
}

type DomainChecker interface {
	IsBlocked(domain string) bool

	GetBlockReason(domain string) string

	CheckDomain(domain string, appName string) string

	HasCustomRule(domain string) int

	IsBlockedForApp(domain string, appName string) bool

	GetBlockReasonForApp(domain string, appName string) string

	HasCustomRuleForApp(domain string, appName string) int
}

type FirewallChecker interface {
	ShouldBlock(appName string) bool
}

type AppResolver interface {
	ResolveApp(sourcePort int, sourceIP []byte, destIP []byte, destPort int) string
}

type AppUidResolver interface {
	PackageForUid(uid int) string
}

type SocketProtector interface {
	Protect(fd int) bool
}

type Stats struct {
	TotalQueries   int64 `json:"total"`
	BlockedQueries int64 `json:"blocked"`
	DroppedLogs    int64 `json:"dropped_logs,omitempty"`
}
