package com.haoze.diting.engine

import java.lang.ref.PhantomReference
import java.lang.ref.ReferenceQueue
import java.util.concurrent.atomic.AtomicBoolean

class Engine : TunnelEngine, AutoCloseable {
    private val handle: Long

    private val released = AtomicBoolean(false)

    private val cleanup: Cleanup

    init {
        NativeLoader.ensureLoaded()
        handle = nativeNew()
        check(handle != 0L) { "engine 初始化失败" }
        cleanup = Cleanup(handle, this)
    }


    fun stop() {
        nativeStop(handle)
    }

    fun flushLogs() {
        nativeFlushLogs(handle)
    }

    override fun isRunning(): Boolean = nativeIsRunning(handle)


    fun startStandalone(port: Int) {
        val error = nativeStartStandalone(handle, port.toLong())
        if (error != null) throw IllegalStateException(error)
    }

    fun startStandaloneLoopback(port: Int) {
        val error = nativeStartStandaloneLoopback(handle, port.toLong())
        if (error != null) throw IllegalStateException(error)
    }

    fun stopStandalone() = nativeStopStandalone(handle)

    fun standalonePort(): Int = nativeStandalonePort(handle).toInt()

    override fun close() {
        if (released.compareAndSet(false, true)) {
            cleanup.clean()
        }
    }


    override fun applyDNSConfig(json: String) {
        val error = nativeApplyDnsConfig(handle, json)
        if (error != null) throw IllegalStateException(error)
    }

    override fun applyRuleSnapshot(payload: ByteArray): String =
        nativeApplyRuleSnapshotBytes(handle, payload)

    override fun setRewriteRules(json: String) {
        nativeSetRewriteRules(handle, json)
    }

    override fun setFilterDNS(enabled: Boolean) {
        nativeSetFilterDns(handle, enabled)
    }

    override fun setBlockPause(untilMs: Long) {
        nativeSetBlockPause(handle, untilMs)
    }

    override fun setAllowlistOnly(enabled: Boolean) {
        nativeSetAllowlistOnly(handle, enabled)
    }

    fun setBlockResponseType(responseType: String) {
        nativeSetBlockResponseType(handle, responseType)
    }

    override fun clearDNSCache() {
        nativeClearDnsCache(handle)
    }


    override fun getStats(): String = nativeGetStats(handle)

    override fun getDNSCacheStats(): String = nativeGetDnsCacheStats(handle)

    override fun statsSnapshot(): ByteArray =
        nativeStatsSnapshot(handle) ?: EMPTY_STATS_SNAPSHOT

    override fun getDNSCacheSnapshot(limit: Long): ByteArray =
        nativeGetDnsCacheSnapshot(handle, limit) ?: EMPTY_CACHE_SNAPSHOT

    override fun flowSnapshot(sinceSeq: Long, limit: Long): String =
        nativeFlowSnapshot(handle, sinceSeq, limit)

    override fun resolveDomain(domain: String, ipv4: Boolean): String =
        nativeResolveDomain(handle, domain, ipv4)


    fun setBatchLogCallback(callback: BatchLogCallback?) {
        nativeSetBatchLogCallback(handle, callback)
    }

    fun setRaceLogCallback(callback: RaceLogCallback?) {
        nativeSetRaceLogCallback(handle, callback)
    }

    fun setBootstrapLogCallback(callback: BootstrapLogCallback?) {
        nativeSetBootstrapLogCallback(handle, callback)
    }


    fun configureOutboundProxy(configJson: String): String =
        nativeConfigureOutboundProxy(handle, configJson) ?: ""

    fun setOutboundProxyStatusCallback(callback: OutboundProxyStatusCallback?) {
        nativeSetOutboundProxyStatusCallback(handle, callback)
    }


    fun startFull(fd: Long, protector: SocketProtector?) {
        if (protector != null) setSocketProtector(protector)
        val error = nativeStartFull(handle, fd)
        if (error != null) throw IllegalStateException(error)
    }

    fun stopFull() {
        nativeStopFull(handle)
    }

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

    fun setFilterHttp3(enabled: Boolean) {
        nativeSetFilterHttp3(handle, enabled)
    }

    fun setBlockEncryptedDns(enabled: Boolean) {
        nativeSetBlockEncryptedDns(handle, enabled)
    }

    fun setBlockIpv6(enabled: Boolean) {
        nativeSetBlockIpv6(handle, enabled)
    }

    fun setSystemDns(serversCsv: String) {
        nativeSetSystemDns(handle, serversCsv)
    }

    fun resetResolverHealth() {
        nativeResetResolverHealth(handle)
    }

    fun setTickIntervalMs(millis: Long) {
        nativeSetTickIntervalMs(handle, millis)
    }

    @Suppress("UNUSED_PARAMETER")
    fun setUseTcpStack(enabled: Boolean) = Unit


    fun startStackMitm(certDir: String): String = nativeStartStackMitm(handle, certDir) ?: ""

    fun stopStackMitm() = nativeStopStackMitm(handle)

    fun isMitmActive(): Boolean = nativeIsMitmActive(handle)

    fun getMitmCACert(certDir: String): String = nativeGetMitmCaCert(handle, certDir) ?: ""

    fun setMitmAllowedUIDs(uidsCsv: String) = nativeSetMitmAllowedUids(handle, uidsCsv)

    fun setHttpsBypassRules(content: String) = nativeSetHttpsBypassRules(handle, content)

    fun setExtraPassthroughSuffixes(content: String) =
        nativeSetExtraPassthroughSuffixes(handle, content)

    fun clearMitmBlacklist() = nativeClearMitmBlacklist(handle)

    fun getMitmBlacklistCount(): Long = nativeMitmBlacklistCount(handle)

    fun setCosmeticRules(json: String) = nativeSetCosmeticRules(handle, json)

    fun setRequestRules(json: String) = nativeSetRequestRules(handle, json)

    fun setHttpLogCallback(callback: HttpLogCallback?) = nativeSetHttpLogCallback(handle, callback)


    private external fun nativeNew(): Long

    private external fun nativeStop(handle: Long)

    private external fun nativeFlushLogs(handle: Long)

    private external fun nativeIsRunning(handle: Long): Boolean

    private external fun nativeStartStandalone(handle: Long, port: Long): String?

    private external fun nativeStartStandaloneLoopback(handle: Long, port: Long): String?

    private external fun nativeStopStandalone(handle: Long)

    private external fun nativeStandalonePort(handle: Long): Long

    private external fun nativeApplyDnsConfig(handle: Long, json: String): String?

    private external fun nativeApplyRuleSnapshotBytes(handle: Long, payload: ByteArray): String

    private external fun nativeSetRewriteRules(handle: Long, json: String)

    private external fun nativeSetFilterDns(handle: Long, enabled: Boolean)

    private external fun nativeSetBlockPause(handle: Long, untilMs: Long)

    private external fun nativeSetAllowlistOnly(handle: Long, enabled: Boolean)

    private external fun nativeSetBlockResponseType(handle: Long, responseType: String)

    private external fun nativeClearDnsCache(handle: Long)

    private external fun nativeGetStats(handle: Long): String

    private external fun nativeGetDnsCacheStats(handle: Long): String

    private external fun nativeStatsSnapshot(handle: Long): ByteArray?

    private external fun nativeGetDnsCacheSnapshot(handle: Long, limit: Long): ByteArray?

    private external fun nativeFlowSnapshot(handle: Long, sinceSeq: Long, limit: Long): String

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

    private external fun nativeSetSystemDns(handle: Long, serversCsv: String)

    private external fun nativeResetResolverHealth(handle: Long)

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
        val EMPTY_CACHE_SNAPSHOT = ByteArray(Int.SIZE_BYTES)

        private val EMPTY_STATS_SNAPSHOT = ByteArray(6 * Long.SIZE_BYTES)

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

        @JvmStatic
        private external fun nativeFree(handle: Long)

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
