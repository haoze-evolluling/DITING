package com.haoze.diting.log

import android.content.Context
import tunnel.AppUidResolver
import tunnel.BootstrapLogCallback
import tunnel.Engine
import tunnel.HttpLogCallback
import tunnel.TrafficCallback
import tunnel.UIDResolver

/// Owns the engine callbacks that feed the log tables; express mode registers only resolvers
class EngineDataPlane(
    private val context: Context,
    private val logMode: String,
    private val databaseName: String = DnsLogWriter.DB_NORMAL,
) {
    private val uidCache = UidPackageCache(context)

    // Lazy: express mode must not start writer threads it never feeds.
    private val traffic: TrafficIngest by lazy {
        TrafficIngest(context, databaseName, uidCache)
    }
    private val http: HttpRequestLogWriter by lazy {
        HttpRequestLogWriter(context, databaseName) { logMode }
    }
    private var trafficAttached = false
    private var httpAttached = false
    private var cacheMirror: DnsCacheMirror? = null

    /// UID -> package lookup for DNS/HTTP attribution and the firewall
    fun attachResolvers(engine: Engine) {
        engine.setUIDResolver(object : UIDResolver {
            override fun resolveUID(
                protocol: Long,
                localIP: String,
                localPort: Long,
                remoteIP: String,
                remotePort: Long,
            ): Long = uidCache.resolveUid(protocol, localIP, localPort, remoteIP, remotePort).toLong()
        })
        engine.setAppUidResolver(object : AppUidResolver {
            override fun packageForUid(uid: Long): String = uidCache.packageForUid(uid.toInt())
        })
    }

    /// Bootstrap race results into `bootstrap_log`; the dashboard card reads only this table
    fun attachBootstrap(engine: Engine) {
        engine.setBootstrapLogCallback(object : BootstrapLogCallback {
            override fun onBootstrapResult(
                ipID: String,
                ipName: String,
                ip: String,
                host: String,
                success: Boolean,
                elapsedMs: Long,
                fallbackUsed: Boolean,
                errorMessage: String,
            ) {
                BootstrapLogWriter.write(
                    context,
                    databaseName,
                    ipId = ipID,
                    ipName = ipName,
                    ip = ip,
                    host = host,
                    success = success,
                    elapsedMs = elapsedMs,
                    fallbackUsed = fallbackUsed,
                    errorMessage = errorMessage,
                )
            }
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
        // Flag first: touching `traffic` starts its executor; a throw must leave it reachable.
        val writer = traffic
        trafficAttached = true
        engine.setTrafficCallback(object : TrafficCallback {
            override fun onTrafficStatsTick(jsonDeltas: String) {
                writer.onTick(jsonDeltas)
            }
        })
    }

    /// MITM events into `http_request_log` (10 rows / 500ms), only while a MITM filter is installed
    fun attachHttp(engine: Engine) {
        val writer = http
        httpAttached = true
        engine.setHttpLogCallback(object : HttpLogCallback {
            override fun onHttpEvent(
                packageName: String,
                authority: String,
                protocol: String,
                outcome: String,
                matchedRule: String,
            ) {
                writer.onEvent(packageName, authority, protocol, outcome, matchedRule)
            }
        })
    }

    /// Flushes what was attached and releases the callback targets; called after the engine stops
    fun close() {
        val mirror = cacheMirror
        cacheMirror = null
        runCatching { mirror?.close() }
        if (trafficAttached) runCatching { traffic.close() }
        if (httpAttached) runCatching { http.close() }
        // Queued DNS / race / bootstrap rows are flushed here: the engine has already stopped, so
        // nothing appends while they are written.
        runCatching { LogTableWriters.closeAll() }
        uidCache.clear()
    }
}
