package com.haoze.diting.log

import android.content.Context
import com.haoze.diting.engine.AppUidResolver
import com.haoze.diting.engine.BootstrapLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.HttpLogCallback
import com.haoze.diting.engine.TrafficCallback
import com.haoze.diting.engine.UIDResolver

class EngineDataPlane(
    private val context: Context,
    private val logMode: String,
    private val databaseName: String,
) {
    private val uidCache = UidPackageCache(context)

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

    fun attachBootstrap(engine: Engine) {
        engineRef = engine
        engine.setBootstrapLogCallback(object : BootstrapLogCallback {
            override fun onBootstrapEvents(rows: ByteArray) = onBootstrapBatch(rows)
        })
    }

    fun attachCacheMirror(engine: Engine) {
        val mirror = DnsCacheMirror(context, databaseName, engine)
        cacheMirror = mirror
        mirror.start()
    }

    fun attachTraffic(engine: Engine) {
        engineRef = engine
        val writer = traffic
        trafficAttached = true
        engine.setTrafficCallback(object : TrafficCallback {
            override fun onTrafficStatsTick(rows: ByteArray) = writer.onTick(rows)
        })
    }

    fun attachHttp(engine: Engine) {
        engineRef = engine
        val writer = http
        httpAttached = true
        engine.setHttpLogCallback(object : HttpLogCallback {
            override fun onHttpEvents(rows: ByteArray) = writer.onEvents(rows)
        })
    }

    fun close() {
        val engine = engineRef
        engineRef = null
        val mirror = cacheMirror
        cacheMirror = null
        runCatching { mirror?.close() }
        runCatching { engine?.flushLogs() }
        runCatching { engine?.setBatchLogCallback(null) }
        runCatching { engine?.setRaceLogCallback(null) }
        runCatching { engine?.setBootstrapLogCallback(null) }
        runCatching { engine?.setTrafficCallback(null) }
        runCatching { engine?.setHttpLogCallback(null) }
        if (trafficAttached) runCatching { traffic.close() }
        if (httpAttached) runCatching { http.close() }
        runCatching { LogTableWriters.closeAll() }
    }


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
