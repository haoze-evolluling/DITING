package com.haoze.diting.engine

import java.lang.ref.PhantomReference
import java.lang.ref.ReferenceQueue
import java.util.concurrent.atomic.AtomicBoolean

/// The Rust engine behind every mode: standalone DNS server, express tunnel and normal tunnel.
///
/// This class is a thin JNI wrapper: the state, the DNS pipeline, the TUN data plane and the MITM
/// relay live in `rust/diting-engine`, and this file only carries the handle. The method names and
/// argument types are frozen by the JNI contract (`rust/diting-engine/src/jni/`), so the call sites
/// read the same as before the Go engine was removed. Three details differ from the old
/// `tunnel.Engine`, and they are the ones the migration plan called out:
///
/// * `applyDNSConfig` and `startStandalone` throw `IllegalStateException` with the engine's error
///   text instead of a checked `Exception`, because the call sites already treated the error as a
///   message;
/// * `close()` replaces the old finalizer: the handle is released deterministically, and a
///   phantom-reference safety net catches the case where a caller dropped the object on an
///   exception path;
/// * `standalonePort()` exists because the Rust server can pick its own port (`startStandalone(0)`).
class Engine : TunnelEngine, AutoCloseable {
    private val handle: Long

    private val released = AtomicBoolean(false)

    /// Safety net for a caller that dropped the engine on an exception path. A phantom reference
    /// works on every supported API; `java.lang.ref.Cleaner` only exists from API 33, which is above
    /// our `minSdk` (28) and used to crash the engine load on Android 9–12.
    private val cleanup: Cleanup

    init {
        NativeLoader.ensureLoaded()
        handle = nativeNew()
        check(handle != 0L) { "engine 初始化失败" }
        // Holds only the handle, so it can run after this object is unreachable.
        cleanup = Cleanup(handle, this)
    }

    // ---- lifecycle -------------------------------------------------------------------------

    /// Stops the DNS server, the TUN session and the resolver.
    fun stop() {
        nativeStop(handle)
    }

    fun stopStandalone() {
        nativeStopStandalone(handle)
    }

    /// Binds UDP and TCP on IPv4 (and IPv6 when the device has it); throws with the bind error.
    fun startStandalone(port: Long) {
        val error = nativeStartStandalone(handle, port)
        if (error != null) throw IllegalStateException(error)
    }

    /// The port the server is listening on, 0 when it is not running.
    fun standalonePort(): Long = nativeStandalonePort(handle)

    override fun isRunning(): Boolean = nativeIsRunning(handle)

    /// Releases the native engine. Idempotent: the second call is a no-op.
    override fun close() {
        if (released.compareAndSet(false, true)) {
            cleanup.clean()
        }
    }

    // ---- configuration ---------------------------------------------------------------------

    override fun applyDNSConfig(json: String) {
        val error = nativeApplyDnsConfig(handle, json)
        if (error != null) throw IllegalStateException(error)
    }

    override fun applyRuleSnapshot(json: String): String = nativeApplyRuleSnapshot(handle, json)

    override fun setRewriteRules(json: String) {
        nativeSetRewriteRules(handle, json)
    }

    override fun setFilterDNS(enabled: Boolean) {
        nativeSetFilterDns(handle, enabled)
    }

    /// `CUSTOM_IP` / `NXDOMAIN` / `REFUSED` / `NODATA`, matched case-sensitively.
    fun setBlockResponseType(responseType: String) {
        nativeSetBlockResponseType(handle, responseType)
    }

    override fun clearDNSCache() {
        nativeClearDnsCache(handle)
    }

    // ---- documents -------------------------------------------------------------------------

    override fun getStats(): String = nativeGetStats(handle)

    override fun getDNSCacheStats(): String = nativeGetDnsCacheStats(handle)

    override fun getDNSCacheEntries(limit: Long): String = nativeGetDnsCacheEntries(handle, limit)

    override fun resolveDomain(domain: String, ipv4: Boolean): String =
        nativeResolveDomain(handle, domain, ipv4)

    // ---- callbacks -------------------------------------------------------------------------

    /// Pass null to stop queueing DNS log rows.
    fun setBatchLogCallback(callback: BatchLogCallback?) {
        nativeSetBatchLogCallback(handle, callback)
    }

    fun setRaceLogCallback(callback: RaceLogCallback?) {
        nativeSetRaceLogCallback(handle, callback)
    }

    fun setBootstrapLogCallback(callback: BootstrapLogCallback?) {
        nativeSetBootstrapLogCallback(handle, callback)
    }

    // ---- outbound proxy (stage 4a) -------------------------------------------------------

    /// `configureOutboundProxy`: "" on success, otherwise the error text the UI shows.
    ///
    /// The kernel normalizes the config (protocol whitelist, loopback host, port range, credentials,
    /// `all` / `apps` scope, positive UIDs); a rejected config leaves the previous one running.
    fun configureOutboundProxy(configJson: String): String =
        nativeConfigureOutboundProxy(handle, configJson) ?: ""

    fun setOutboundProxyStatusCallback(callback: OutboundProxyStatusCallback?) {
        nativeSetOutboundProxyStatusCallback(handle, callback)
    }

    // ---- TUN data plane (stage 3) ---------------------------------------------------------

    /// Starts the tunnel on `fd` and installs the `protect` callback first.
    ///
    /// The protector is installed before the start so the very first upstream query of the TUN
    /// session is already protected; a refused `protect` fails that dial closed instead of sending
    /// traffic around the tunnel. Throws with the engine's error text when the descriptor cannot be
    /// duplicated or the session threads cannot start.
    fun startFull(fd: Long, protector: SocketProtector?) {
        if (protector != null) setSocketProtector(protector)
        val error = nativeStartFull(handle, fd)
        if (error != null) throw IllegalStateException(error)
    }

    /// `stop()` already stops the data plane; this is the explicit form.
    fun stopFull() {
        nativeStopFull(handle)
    }

    /// Stops the session and releases the TUN (the session owns its `dup`, so stopping is the
    /// release).
    fun releaseTun() {
        nativeReleaseTun(handle)
    }

    fun isFullRunning(): Boolean = nativeIsFullRunning(handle)

    fun setSocketProtector(callback: SocketProtector?) {
        nativeSetSocketProtector(handle, callback)
    }

    fun setUIDResolver(callback: UIDResolver?) {
        nativeSetUidResolver(handle, callback)
    }

    fun setAppUidResolver(callback: AppUidResolver?) {
        nativeSetAppUidResolver(handle, callback)
    }

    fun setTrafficCallback(callback: TrafficCallback?) {
        nativeSetTrafficCallback(handle, callback)
    }

    fun setBlockedUIDs(uidsCsv: String) {
        nativeSetBlockedUids(handle, uidsCsv)
    }

    /// Drops `UDP :443` so HTTP/3 falls back to TCP; only meaningful with a MITM UID set (stage 4b).
    fun setFilterHttp3(enabled: Boolean) {
        nativeSetFilterHttp3(handle, enabled)
    }

    /// Refuses `TCP/UDP :853`.
    fun setBlockEncryptedDns(enabled: Boolean) {
        nativeSetBlockEncryptedDns(handle, enabled)
    }

    /// Answers AAAA with NODATA while the tunnel has no usable IPv6, so clients fall back to IPv4
    /// instead of stalling on a dual-stack retry.
    fun setBlockIpv6(enabled: Boolean) {
        nativeSetBlockIpv6(handle, enabled)
    }

    /// Stretches the traffic tick when the screen is off.
    fun setTickIntervalMs(millis: Long) {
        nativeSetTickIntervalMs(handle, millis)
    }

    /// `setUseTcpStack` is a no-op: the engine always uses the stack when a TUN session is running,
    /// so the method exists for call-site parity only.
    @Suppress("UNUSED_PARAMETER")
    fun setUseTcpStack(enabled: Boolean) = Unit

    // ---- MITM (stage 4b) -----------------------------------------------------------------

    /// `startStackMitm(certDir)`: the root CA in PEM form, or "" when MITM could not start (the
    /// failure is logged by the engine; callers treat "" as "no interception").
    ///
    /// `certDir` is the app's `.go-mitm` directory; `ca.crt`/`ca.key` are loaded when both exist and
    /// generated (and persisted) otherwise, so a root the user already installed keeps validating.
    fun startStackMitm(certDir: String): String = nativeStartStackMitm(handle, certDir) ?: ""

    /// Tears the session down and drops every minted leaf; the CA stays on disk.
    fun stopStackMitm() = nativeStopStackMitm(handle)

    fun isMitmActive(): Boolean = nativeIsMitmActive(handle)

    /// The installed root: from the live session, otherwise from `certDir/ca.crt`.
    fun getMitmCACert(certDir: String): String = nativeGetMitmCaCert(handle, certDir) ?: ""

    /// The per-app interception list. An empty list relays everything.
    fun setMitmAllowedUIDs(uidsCsv: String) = nativeSetMitmAllowedUids(handle, uidsCsv)

    /// Host patterns that are never decrypted (`#`/`//` comments allowed).
    fun setHttpsBypassRules(content: String) = nativeSetHttpsBypassRules(handle, content)

    /// The platform channel's name for the same list.
    fun setExtraPassthroughSuffixes(content: String) =
        nativeSetExtraPassthroughSuffixes(handle, content)

    fun clearMitmBlacklist() = nativeClearMitmBlacklist(handle)

    /// Live auto-blacklist entries, for the settings screen.
    fun getMitmBlacklistCount(): Long = nativeMitmBlacklistCount(handle)

    /// `{"globalHide":[…],"globalException":[…],"domains":{…}}`; an empty string disables injection.
    fun setCosmeticRules(json: String) = nativeSetCosmeticRules(handle, json)

    /// `[{"pattern":"https://example.com/path","kind":"block"}]`, matched per request.
    fun setRequestRules(json: String) = nativeSetRequestRules(handle, json)

    /// One row per relayed request/response; null stops reporting.
    fun setHttpLogCallback(callback: HttpLogCallback?) = nativeSetHttpLogCallback(handle, callback)

    // ---- JNI -------------------------------------------------------------------------------

    private external fun nativeNew(): Long

    private external fun nativeStop(handle: Long)

    private external fun nativeStopStandalone(handle: Long)

    private external fun nativeStartStandalone(handle: Long, port: Long): String?

    private external fun nativeStandalonePort(handle: Long): Long

    private external fun nativeIsRunning(handle: Long): Boolean

    private external fun nativeApplyDnsConfig(handle: Long, json: String): String?

    private external fun nativeApplyRuleSnapshot(handle: Long, json: String): String

    private external fun nativeSetRewriteRules(handle: Long, json: String)

    private external fun nativeSetFilterDns(handle: Long, enabled: Boolean)

    private external fun nativeSetBlockResponseType(handle: Long, responseType: String)

    private external fun nativeClearDnsCache(handle: Long)

    private external fun nativeGetStats(handle: Long): String

    private external fun nativeGetDnsCacheStats(handle: Long): String

    private external fun nativeGetDnsCacheEntries(handle: Long, limit: Long): String

    private external fun nativeResolveDomain(handle: Long, domain: String, ipv4: Boolean): String

    private external fun nativeSetBatchLogCallback(handle: Long, callback: BatchLogCallback?)

    private external fun nativeSetRaceLogCallback(handle: Long, callback: RaceLogCallback?)

    private external fun nativeSetBootstrapLogCallback(handle: Long, callback: BootstrapLogCallback?)

    private external fun nativeStartFull(handle: Long, fd: Long): String?

    private external fun nativeStopFull(handle: Long)

    private external fun nativeReleaseTun(handle: Long)

    private external fun nativeIsFullRunning(handle: Long): Boolean

    private external fun nativeSetSocketProtector(handle: Long, callback: SocketProtector?)

    private external fun nativeSetUidResolver(handle: Long, callback: UIDResolver?)

    private external fun nativeSetAppUidResolver(handle: Long, callback: AppUidResolver?)

    private external fun nativeSetTrafficCallback(handle: Long, callback: TrafficCallback?)

    private external fun nativeSetBlockedUids(handle: Long, uidsCsv: String)

    private external fun nativeSetFilterHttp3(handle: Long, enabled: Boolean)

    private external fun nativeSetBlockEncryptedDns(handle: Long, enabled: Boolean)

    private external fun nativeSetBlockIpv6(handle: Long, enabled: Boolean)

    private external fun nativeSetTickIntervalMs(handle: Long, millis: Long)

    private external fun nativeConfigureOutboundProxy(handle: Long, configJson: String): String?

    private external fun nativeSetOutboundProxyStatusCallback(
        handle: Long,
        callback: OutboundProxyStatusCallback?,
    )

    private external fun nativeStartStackMitm(handle: Long, certDir: String): String?

    private external fun nativeStopStackMitm(handle: Long)

    private external fun nativeIsMitmActive(handle: Long): Boolean

    private external fun nativeGetMitmCaCert(handle: Long, certDir: String): String?

    private external fun nativeSetMitmAllowedUids(handle: Long, uidsCsv: String)

    private external fun nativeSetHttpsBypassRules(handle: Long, content: String)

    private external fun nativeSetExtraPassthroughSuffixes(handle: Long, content: String)

    private external fun nativeClearMitmBlacklist(handle: Long)

    private external fun nativeMitmBlacklistCount(handle: Long): Long

    private external fun nativeSetCosmeticRules(handle: Long, payload: String)

    private external fun nativeSetRequestRules(handle: Long, payload: String)

    private external fun nativeSetHttpLogCallback(handle: Long, callback: HttpLogCallback?)

    private companion object {
        /// Engines dropped without `close()` land here for the cleanup thread.
        private val deadEngines = ReferenceQueue<Engine>()

        init {
            Thread({
                while (true) {
                    val reference = try {
                        deadEngines.remove()
                    } catch (ignored: InterruptedException) {
                        continue
                    }
                    (reference as? Cleanup)?.clean()
                }
            }, "engine-cleanup").apply { isDaemon = true }.start()
        }

        /// Static so the cleanup action can call it without keeping the engine alive.
        @JvmStatic
        private external fun nativeFree(handle: Long)

        /// Phantom reference that frees the native handle once the engine is unreachable; holds the
        /// handle and nothing else. Works on every API (unlike `java.lang.ref.Cleaner`).
        class Cleanup(handle: Long, engine: Engine) : PhantomReference<Engine>(engine, deadEngines) {
            private val target = handle
            private val freed = AtomicBoolean(false)

            fun clean() {
                if (freed.compareAndSet(false, true)) {
                    nativeFree(target)
                }
            }
        }
    }
}
