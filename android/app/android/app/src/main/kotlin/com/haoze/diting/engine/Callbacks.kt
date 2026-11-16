package com.haoze.diting.engine

/// The engine callbacks the Rust side calls, with the names and argument lists the JNI contract
/// spells (`rust/diting-engine/src/jni/`).
///
/// The signatures are part of the JNI contract: `rust/diting-engine/src/jni/callbacks.rs` spells the
/// descriptors, and `rust/tools/engine-smoke/com/haoze/diting/engine/Engine.java` declares the same
/// three interfaces, so a changed argument list fails on the host rather than on a phone.
///
/// Every callback arrives on an engine thread (the log flusher for DNS batches, the event flusher
/// for race/bootstrap batches), never on the thread that installed it.
interface BatchLogCallback {
    /// One packed `dns_log` batch in the log kernel's input layout; forward it to
    /// `LogNative.dnsBatchSubmit`.
    fun onDNSQueryBatch(rows: ByteArray)
}

/// One packed race batch: `u32 count | rows(u32 length | bytes)`, each row in the layout
/// `rust/diting-log-core/src/api/mod.rs` documents for a race input.
interface RaceLogCallback {
    fun onRaceEvents(rows: ByteArray)
}

/// One packed bootstrap batch, shaped like [RaceLogCallback.onRaceEvents].
interface BootstrapLogCallback {
    fun onBootstrapEvents(rows: ByteArray)
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
/// `localAddress`/`localPort` are the **app** endpoint and `remoteAddress`/`remotePort` the
/// destination the app dialed, which is the pair Android's API wants (and the reverse of what the
/// stack's naming might suggest). The addresses are the raw 4- or 16-byte wire form, so the caller
/// hands them straight to `InetAddress.getByAddress` instead of parsing two strings.
interface UIDResolver {
    fun resolveUID(
        protocol: Long,
        localAddress: ByteArray,
        localPort: Long,
        remoteAddress: ByteArray,
        remotePort: Long,
    ): Long
}

/// `PackageManager.getPackagesForUid`; an empty string means "unknown".
interface AppUidResolver {
    fun packageForUid(uid: Long): String
}

/// Per-UID byte deltas, one packed batch per tick:
/// `u32 count | (i32 uid, i64 tx, i64 rx, string package)`. The package name is resolved by the
/// engine, so the JVM only prepends the date and forwards the buffer.
interface TrafficCallback {
    fun onTrafficStatsTick(rows: ByteArray)
}

/// `OutboundProxyStatusCallback.onOutboundProxyStatus`: `disabled` / `connecting` / `ready` /
/// `error`, written straight into `dns_vpn_prefs` by `OutboundProxyBridge.publishStatus`.
interface OutboundProxyStatusCallback {
    fun onOutboundProxyStatus(state: String, message: String)
}

/// `HttpLogCallback.onHttpEvents`: one packed batch of MITM relay decisions.
///
/// The engine buffers rows and hands them over in batches, because the relay path can produce
/// dozens of decisions per page. Each event is `(package, authority, protocol, outcome,
/// matchedRule)` with the payload layout `rust/diting-engine/src/jni/adapters.rs` documents;
/// `outcome` is one of `allowed`, `blocked`, `passthrough`, `rewritten`, `error`,
/// `handshake_failed`, `upstream_failed`, `decryption_failed`, and `matchedRule` is empty for
/// `allowed`.
interface HttpLogCallback {
    fun onHttpEvents(rows: ByteArray)
}

/// The subset of the engine that the shared log/diagnostics code uses.
///
/// Keeping it this small is deliberate: everything the VPN data plane needs (`setUIDResolver`,
/// `startFull`, `protect`, …) stays on `Engine` and does not appear here, so a diagnostics caller
/// cannot reach the data plane by accident.
interface TunnelEngine {
    /// Throws when the config document is rejected.
    fun applyDNSConfig(json: String)

    /// Empty on success, otherwise the rejection text. The document is passed as the UTF-8 bytes
    /// the rule kernel built, so a large snapshot is never widened to a Java `String`.
    fun applyRuleSnapshot(payload: ByteArray): String

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

    /// Six big-endian `u64`s: `total | blocked | droppedLogs | cacheHits | cacheMisses |
    /// cacheEntries`. One crossing replaces the two JSON documents above on the polling path.
    fun statsSnapshot(): ByteArray

    /// The hottest live cache entries, packed in the log kernel's mirror input layout.
    fun getDNSCacheSnapshot(limit: Long): ByteArray

    /// N4: incremental live-connection document `{baseSeq,nextSeq,total,truncated,sessions[]}`.
    fun flowSnapshot(sinceSeq: Long, limit: Long): String

    /// `{"ips":…,"source":…}` or `{"source":"","error":…}`.
    fun resolveDomain(domain: String, ipv4: Boolean): String

    fun isRunning(): Boolean
}
