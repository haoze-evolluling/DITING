package com.haoze.diting.engine

/// The engine callbacks the Rust side calls, with the names and argument lists the JNI contract
/// spells (`rust/diting-engine/src/jni/`).
///
/// The signatures are part of the JNI contract: `rust/diting-engine/src/jni/callbacks.rs` spells the
/// descriptors, and `rust/tools/engine-smoke/com/haoze/diting/engine/Engine.java` declares the same
/// three interfaces, so a changed argument list fails on the host rather than on a phone.
///
/// Every callback arrives on an engine thread (the log flusher for batches, a tokio worker for the
/// race and bootstrap rows), never on the thread that installed it.
interface BatchLogCallback {
    /// One JSON array of `d`/`b`/`t`/`r`/`a`/`i`/`k`/`e`/`c`/`ts`/`ttl` rows.
    fun onDNSQueryBatch(jsonLogs: String)
}

interface RaceLogCallback {
    fun onRaceResult(
        queryName: String,
        queryType: Long,
        strategy: String,
        providerCount: Long,
        success: Boolean,
        elapsedMs: Long,
        selectedProviderID: String,
        selectedElapsedMs: Long,
        winnerProviderID: String,
        winnerElapsedMs: Long,
        fallbackUsed: Boolean,
        fallbackSuccess: Boolean,
        errorMessage: String,
    )
}

interface BootstrapLogCallback {
    fun onBootstrapResult(
        ipID: String,
        ipName: String,
        ip: String,
        host: String,
        success: Boolean,
        elapsedMs: Long,
        fallbackUsed: Boolean,
        errorMessage: String,
    )
}

/// `VpnService.protect(int)`: the socket must bypass the tunnel before it connects.
///
/// `fd` is the `long` the JNI descriptor spells; `VpnService.protect` takes an `Int`, so the Kotlin
/// implementation converts once (`protect(fd.toInt())`). `false` fails the dial closed — the engine
/// never falls back to an unprotected connect.
interface SocketProtector {
    fun protect(fd: Long): Boolean
}

/// `ConnectivityManager.getConnectionOwnerUid` behind the engine's caches.
///
/// `localIP`/`localPort` are the **app** endpoint and `remoteIP`/`remotePort` the destination the
/// app dialed, which is the pair Android's API wants (and the reverse of what the stack's naming
/// might suggest).
interface UIDResolver {
    fun resolveUID(
        protocol: Long,
        localIP: String,
        localPort: Long,
        remoteIP: String,
        remotePort: Long,
    ): Long
}

/// `PackageManager.getPackagesForUid`; an empty string means "unknown".
interface AppUidResolver {
    fun packageForUid(uid: Long): String
}

/// Per-UID byte deltas, one JSON array per tick: `[{"uid":…,"tx":…,"rx":…}]`.
interface TrafficCallback {
    fun onTrafficStatsTick(jsonDeltas: String)
}

/// `OutboundProxyStatusCallback.onOutboundProxyStatus`: `disabled` / `connecting` / `ready` /
/// `error`, written straight into `dns_vpn_prefs` by `OutboundProxyBridge.publishStatus`.
interface OutboundProxyStatusCallback {
    fun onOutboundProxyStatus(state: String, message: String)
}

/// `HttpLogCallback.onHttpEvent`: one row per MITM relay decision.
///
/// `outcome` is one of `allowed`, `blocked`, `passthrough`, `rewritten`, `error`,
/// `handshake_failed`, `upstream_failed`, `decryption_failed`; `matchedRule` carries the rule, the
/// refusal reason or the rewrite target, and is empty for `allowed`.
interface HttpLogCallback {
    fun onHttpEvent(
        packageName: String,
        authority: String,
        protocol: String,
        outcome: String,
        matchedRule: String,
    )
}

/// The subset of the engine that the shared log/diagnostics code uses.
///
/// Keeping it this small is deliberate: everything the VPN data plane needs (`setUIDResolver`,
/// `startFull`, `protect`, …) stays on `Engine` and does not appear here, so a diagnostics caller
/// cannot reach the data plane by accident.
interface TunnelEngine {
    /// Throws when the config document is rejected.
    fun applyDNSConfig(json: String)

    /// Empty on success, otherwise the rejection text.
    fun applyRuleSnapshot(json: String): String

    fun setRewriteRules(json: String)

    fun setFilterDNS(enabled: Boolean)

    /// R4: skip every policy block until `untilMs` (epoch ms); `0` clears the pause.
    fun setBlockPause(untilMs: Long)

    /// R4: block anything that is not an explicit allow.
    fun setAllowlistOnly(enabled: Boolean)

    fun clearDNSCache()

    /// `{"total":…,"blocked":…,"dropped_logs":…}`.
    fun getStats(): String

    /// `{"enabled":…,"totalHits":…,"entryCount":…}`.
    fun getDNSCacheStats(): String

    /// A JSON array of live cache entries, hottest first.
    fun getDNSCacheEntries(limit: Long): String

    /// N4: incremental live-connection document `{baseSeq,nextSeq,total,truncated,sessions[]}`.
    fun flowSnapshot(sinceSeq: Long, limit: Long): String

    /// `{"ips":…,"source":…}` or `{"source":"","error":…}`.
    fun resolveDomain(domain: String, ipv4: Boolean): String

    fun isRunning(): Boolean
}
