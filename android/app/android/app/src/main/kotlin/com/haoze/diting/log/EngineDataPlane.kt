package com.haoze.diting.log

import android.content.Context
import com.haoze.diting.engine.AppUidResolver
import com.haoze.diting.engine.BootstrapLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.HttpLogCallback
import com.haoze.diting.engine.TrafficCallback
import com.haoze.diting.engine.UIDResolver

/// Owns the engine callbacks that feed the log tables; express mode registers only resolvers.
///
/// Every mode runs on the Rust engine since stage 4b-2, so there is one overload per callback and
/// the payload handling lives in the methods at the bottom of the class — the only place a writer
/// call is allowed to live.
class EngineDataPlane(
    private val context: Context,
    private val logMode: String,
    private val databaseName: String,
) {
    private val uidCache = UidPackageCache(context)

    // Lazy: express mode must not start writer threads it never feeds.
    private val traffic: TrafficIngest by lazy {
        TrafficIngest(context, databaseName)
    }
    private val http: HttpRequestLogWriter by lazy {
        HttpRequestLogWriter(context, databaseName) { logMode }
    }
    private var trafficAttached = false
    private var httpAttached = false
    private var cacheMirror: DnsCacheMirror? = null
    private var engineRef: Engine? = null

    /// UID -> package lookup for DNS/HTTP attribution and the firewall
    fun attachResolvers(engine: Engine) {
        engineRef = engine
        engine.setUIDResolver(object : UIDResolver {
            override fun resolveUID(
                protocol: Long,
                localAddress: ByteArray,
                localPort: Long,
                remoteAddress: ByteArray,
                remotePort: Long,
            ): Long = resolveUid(protocol, localAddress, localPort, remoteAddress, remotePort)
        })
        engine.setAppUidResolver(object : AppUidResolver {
            override fun packageForUid(uid: Long): String = this@EngineDataPlane.packageForUid(uid)
        })
    }

    /// Bootstrap race results into `bootstrap_log`; the dashboard card reads only this table
    fun attachBootstrap(engine: Engine) {
        engineRef = engine
        engine.setBootstrapLogCallback(object : BootstrapLogCallback {
            override fun onBootstrapEvents(rows: ByteArray) = onBootstrapBatch(rows)
        })
    }

    /// Periodic copy of the engine's in-memory LRU into `dns_cache`, which the UI reads
    fun attachCacheMirror(engine: Engine) {
        val mirror = DnsCacheMirror(context, databaseName, engine)
        cacheMirror = mirror
        mirror.start()
    }

    /// Per-UID byte deltas into `app_traffic_daily` (buffered 15s / 1MB). Full tunnel only
    fun attachTraffic(engine: Engine) {
        engineRef = engine
        // Flag first: touching `traffic` starts its executor; a throw must leave it reachable.
        val writer = traffic
        trafficAttached = true
        engine.setTrafficCallback(object : TrafficCallback {
            override fun onTrafficStatsTick(rows: ByteArray) = writer.onTick(rows)
        })
    }

    /// MITM events into `http_request_log` (10 rows / 500ms); only normal mode with HTTPS
    /// inspection on installs a filter, so any other mode simply never sees a row.
    fun attachHttp(engine: Engine) {
        engineRef = engine
        val writer = http
        httpAttached = true
        engine.setHttpLogCallback(object : HttpLogCallback {
            override fun onHttpEvents(rows: ByteArray) = writer.onEvents(rows)
        })
    }

    /// Flushes what was attached and releases the callback targets; called after the engine stops
    fun close() {
        val engine = engineRef
        engineRef = null
        val mirror = cacheMirror
        cacheMirror = null
        runCatching { mirror?.close() }
        // Deliver the engine's own buffers first: its DNS flusher and the race/bootstrap event
        // flusher may still hold a partial batch that would otherwise arrive after the queues close.
        runCatching { engine?.flushLogs() }
        // Stop every callback before the queues close. Clearing the last one joins the engine's
        // flushers, so nothing can call into a writer below.
        runCatching { engine?.setBatchLogCallback(null) }
        runCatching { engine?.setRaceLogCallback(null) }
        runCatching { engine?.setBootstrapLogCallback(null) }
        runCatching { engine?.setTrafficCallback(null) }
        // Dropping the callback joins the engine's HTTP flusher, which delivers the buffered tail
        // here, while the writer is still open and can queue it.
        runCatching { engine?.setHttpLogCallback(null) }
        if (trafficAttached) runCatching { traffic.close() }
        if (httpAttached) runCatching { http.close() }
        // Queued DNS / race / bootstrap rows are flushed here: the engine has already stopped, so
        // nothing appends while they are written.
        runCatching { LogTableWriters.closeAll() }
    }

    // ---- payload handling, shared by every callback -----------------------------------------

    private fun resolveUid(
        protocol: Long,
        localAddress: ByteArray,
        localPort: Long,
        remoteAddress: ByteArray,
        remotePort: Long,
    ): Long = uidCache.resolveUid(protocol, localAddress, localPort, remoteAddress, remotePort).toLong()

    private fun packageForUid(uid: Long): String = uidCache.packageForUid(uid.toInt())

    private fun onBootstrapBatch(rows: ByteArray) {
        BootstrapLogWriter.writeBatch(context, databaseName, rows)
    }
}
