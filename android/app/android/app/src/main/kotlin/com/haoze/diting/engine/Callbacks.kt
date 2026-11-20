package com.haoze.diting.engine

interface BatchLogCallback {
    fun onDNSQueryBatch(rows: ByteArray)
}

interface RaceLogCallback {
    fun onRaceEvents(rows: ByteArray)
}

interface BootstrapLogCallback {
    fun onBootstrapEvents(rows: ByteArray)
}

interface SocketProtector {
    fun protect(fd: Long): Boolean
}

interface UIDResolver {
    fun resolveUID(
        protocol: Long,
        localAddress: ByteArray,
        localPort: Long,
        remoteAddress: ByteArray,
        remotePort: Long,
    ): Long
}

interface AppUidResolver {
    fun packageForUid(uid: Long): String
}

interface TrafficCallback {
    fun onTrafficStatsTick(rows: ByteArray)
}

interface OutboundProxyStatusCallback {
    fun onOutboundProxyStatus(state: String, message: String)
}

interface HttpLogCallback {
    fun onHttpEvents(rows: ByteArray)
}

interface TunnelEngine {
    fun applyDNSConfig(json: String)

    fun applyRuleSnapshot(payload: ByteArray): String

    fun setRewriteRules(json: String)

    fun setFilterDNS(enabled: Boolean)

    fun setBlockPause(untilMs: Long)

    fun setAllowlistOnly(enabled: Boolean)

    fun clearDNSCache()

    fun getStats(): String

    fun getDNSCacheStats(): String

    fun statsSnapshot(): ByteArray

    fun getDNSCacheSnapshot(limit: Long): ByteArray

    fun flowSnapshot(sinceSeq: Long, limit: Long): String

    fun resolveDomain(domain: String, ipv4: Boolean): String

    fun isRunning(): Boolean
}
