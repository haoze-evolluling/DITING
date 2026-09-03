package tunnel

// LogCallback is the interface for receiving DNS query events in Kotlin.
// gomobile will generate the corresponding Java/Kotlin interface.
type LogCallback interface {
	// OnDNSQuery is called for each DNS query processed.
	OnDNSQuery(domain string, blocked bool, queryType int, responseTimeMs int64, appName string, resolvedIPs string, blockedBy string, errorMessage string, cached bool)
}

// BatchLogCallback is the interface for receiving batched DNS and connection query events in Kotlin.
type BatchLogCallback interface {
	OnDNSQueryBatch(jsonLogs string)
}

// RaceLogCallback is the interface for receiving DNS race and resolution strategy events in Kotlin.
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

// HttpLogCallback receives the minimal metadata produced by the MITM path.
// It intentionally excludes paths, headers, bodies, and decrypted payloads.
type HttpLogCallback interface {
	OnHttpEvent(packageName string, authority string, protocol string, outcome string, matchedRule string)
}

type OutboundProxyStatusCallback interface {
	OnOutboundProxyStatus(state string, message string)
}

// DomainChecker is the interface for checking if a domain should be blocked.
// The implementation lives in Kotlin (using efficient mmap'd Trie data structures)
// so we don't need to export 200k+ domains to Go.
type DomainChecker interface {
	// IsBlocked returns true if the domain should be blocked.
	IsBlocked(domain string) bool
	// GetBlockReason returns the reason a domain is blocked (e.g., "ad", "security", "custom").
	// Returns empty string if not blocked.
	GetBlockReason(domain string) string
	// CheckDomain performs a unified, single-shot evaluation:
	// Returns "" for default pass (no rule match),
	// "__ALLOW__" for explicit allow override,
	// or non-empty string as the block reason (e.g., "custom", "filter_list", rule pattern).
	CheckDomain(domain string, appName string) string
	// HasCustomRule checks if a domain matches a custom allow or block rule.
	// Returns 1 for block override, 0 for allow override, -1 for no override.
	HasCustomRule(domain string) int
	// IsBlockedForApp checks if domain is blocked for a specific app package.
	IsBlockedForApp(domain string, appName string) bool
	// GetBlockReasonForApp returns block reason for a specific app package.
	GetBlockReasonForApp(domain string, appName string) string
	// HasCustomRuleForApp checks custom rule override for a specific app package.
	HasCustomRuleForApp(domain string, appName string) int
}

// FirewallChecker checks if a DNS query from a specific app should be blocked.
// The implementation lives in Kotlin and uses UID resolution + FirewallManager.
type FirewallChecker interface {
	// ShouldBlock checks if the app owning the DNS connection should be blocked.
	ShouldBlock(appName string) bool
}

// AppResolver interface to allow Kotlin to return the AppName for a connection
type AppResolver interface {
	ResolveApp(sourcePort int, sourceIP []byte, destIP []byte, destPort int) string
}

// AppUidResolver maps an Android UID → package name (Kotlin-side, via
// PackageManager.getPackagesForUid). The UID comes from
// getConnectionOwnerUid. Unlike AppResolver it takes only an int (no
// []byte), so it is safe to call from the concurrent full-tunnel flow hot
// path — passing Go []byte to the gomobile JNI there panics under Go's
// cgocheck ("Go pointer to unpinned Go pointer").
type AppUidResolver interface {
	PackageForUid(uid int) string
}

// SocketProtector is the interface for protecting sockets from VPN routing loop.
// Implemented in Kotlin via VpnService.protect().
type SocketProtector interface {
	// Protect protects a socket file descriptor from the VPN routing loop.
	Protect(fd int) bool
}

// Stats holds engine statistics.
type Stats struct {
	TotalQueries   int64 `json:"total"`
	BlockedQueries int64 `json:"blocked"`
	DroppedLogs    int64 `json:"dropped_logs,omitempty"`
}
