package com.haoze.diting.server.backend

import android.util.Log
import com.haoze.diting.server.model.DnsModeConfig
import com.haoze.diting.server.model.DnsModeProtocol
import com.haoze.diting.server.model.DnsUpstreamServer
import com.haoze.diting.core.rule.DomainDecision
import org.json.JSONArray
import org.json.JSONObject
import tunnel.DomainChecker
import tunnel.Engine
import tunnel.LogCallback
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * High-performance standalone DNS server backed by the unified Go tunnel data plane.
 * Binds on 0.0.0.0 (UDP/TCP) to accept LAN queries and evaluates them using Go's
 * PolicyEngine, Go native cache, and native Go resolvers.
 */
class DnsServerEngine(
    @Volatile private var config: DnsModeConfig,
    @Volatile private var upstream: DnsUpstreamServer,
    private val onQueryProcessed: ((cacheHit: Boolean, blocked: Boolean, failed: Boolean, latencyMs: Long) -> Unit)? = null,
    private val queryFilter: DnsQueryFilter? = null
) {
    private val engine: Engine by lazy { Engine() }

    @Volatile
    private var isRunning: Boolean = false

    val isEngineRunning: Boolean get() = isRunning

    @Synchronized
    fun start(): Boolean {
        if (isRunning) return true
        val port = config.localListenPort
        return try {
            configureEngine()
            engine.startStandalone(port.toLong())
            isRunning = true
            Log.i(TAG, "Go standalone DNS server successfully listening on 0.0.0.0:$port (UDP & TCP)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Go standalone DNS server on port $port", e)
            stop()
            false
        }
    }

    @Synchronized
    fun stop() {
        isRunning = false
        runCatching { engine.stopStandalone() }
            .onFailure { runCatching { engine.stop() } }
        Log.i(TAG, "Go standalone DNS server stopped")
    }

    /**
     * Applies a config/upstream change. Returns whether the engine is running
     * afterwards; a failed port-change restart surfaces as false so the caller
     * can stop the service instead of reporting RUNNING with a dead engine.
     */
    @Synchronized
    fun updateConfig(newConfig: DnsModeConfig, newUpstream: DnsUpstreamServer): Boolean {
        val portChanged = newConfig.localListenPort != config.localListenPort
        val upstreamChanged = newUpstream != upstream
        val filteringChanged = newConfig.adBlockEnabled != config.adBlockEnabled
        val cacheChanged = newConfig.cacheEnabled != config.cacheEnabled ||
            newConfig.cachePreset != config.cachePreset ||
            newConfig.cacheTtlSeconds != config.cacheTtlSeconds

        config = newConfig
        upstream = newUpstream

        if (portChanged && isRunning) {
            Log.i(TAG, "Port changed to ${newConfig.localListenPort}, restarting Go standalone DNS server")
            stop()
            return start()
        }

        if (isRunning) {
            if (upstreamChanged || cacheChanged) {
                applyDnsConfig()
            }
            if (filteringChanged) {
                engine.setFilterDNS(config.adBlockEnabled)
            }
        }
        return isRunning
    }

    fun syncRules() {
        val filter = queryFilter ?: return
        runCatching {
            val snapshotJson = filter.buildRuleSnapshotJson()
            val err = engine.applyRuleSnapshot(snapshotJson)
            if (!err.isNullOrBlank()) {
                Log.w(TAG, "applyRuleSnapshot error: $err")
            }
            engine.setRewriteRules(filter.buildRewriteRulesJson())
            engine.setBlockResponseType(filter.blockResponseMode.name)
            engine.clearDNSCache()
        }.onFailure { Log.e(TAG, "Failed to sync rules to Go engine", it) }
    }

    private fun configureEngine() {
        applyDnsConfig()
        engine.setFilterDNS(config.adBlockEnabled)

        if (queryFilter != null) {
            syncRules()
            engine.setDomainChecker(object : DomainChecker {
                override fun checkDomain(domain: String, appName: String): String =
                    when (val decision = queryFilter.policy.evaluate(domain, appName.ifBlank { null })) {
                        is DomainDecision.Block -> decision.matchedRule.ifEmpty { "custom" }
                        is DomainDecision.Allow -> if (decision.matchedRule != null) "__ALLOW__" else ""
                    }

                override fun isBlocked(domain: String): Boolean =
                    queryFilter.policy.evaluate(domain) is DomainDecision.Block

                override fun getBlockReason(domain: String): String =
                    (queryFilter.policy.evaluate(domain) as? DomainDecision.Block)?.matchedRule.orEmpty()

                override fun hasCustomRule(domain: String): Long =
                    when (val decision = queryFilter.policy.evaluate(domain)) {
                        is DomainDecision.Block -> 1L
                        is DomainDecision.Allow -> if (decision.matchedRule != null) 0L else -1L
                    }

                override fun isBlockedForApp(domain: String, appName: String): Boolean =
                    queryFilter.policy.evaluate(domain, appName.ifBlank { null }) is DomainDecision.Block

                override fun getBlockReasonForApp(domain: String, appName: String): String =
                    (queryFilter.policy.evaluate(domain, appName.ifBlank { null }) as? DomainDecision.Block)?.matchedRule.orEmpty()

                override fun hasCustomRuleForApp(domain: String, appName: String): Long =
                    when (val decision = queryFilter.policy.evaluate(domain, appName.ifBlank { null })) {
                        is DomainDecision.Block -> 1L
                        is DomainDecision.Allow -> if (decision.matchedRule != null) 0L else -1L
                    }
            })
        }

        engine.setLogCallback(object : LogCallback {
            override fun onDNSQuery(
                domain: String,
                blocked: Boolean,
                queryType: Long,
                responseTimeMs: Long,
                appName: String,
                resolvedIPs: String,
                blockedBy: String,
                errorMessage: String,
                cached: Boolean
            ) {
                val failed = errorMessage.isNotBlank()
                onQueryProcessed?.invoke(cached, blocked, failed, responseTimeMs)
            }
        })
    }

    private fun applyDnsConfig() {
        val json = JSONObject().apply {
            put("mode", "single")
            put("blockResponse", queryFilter?.blockResponseMode?.name ?: "NXDOMAIN")
            val cachePolicy = config.cachePreset.toPolicy(enabled = config.cacheEnabled)
            put("cache", JSONObject().apply {
                put("enabled", cachePolicy.enabled)
                put("mode", cachePolicy.mode.storageValue)
                put("maxTtlSeconds", cachePolicy.maxTtlSeconds)
                put("fixedTtlSeconds", cachePolicy.fixedTtlSeconds)
                put("minTtlEnabled", cachePolicy.minTtlEnabled)
                put("minTtlSeconds", cachePolicy.minTtlSeconds)
                put("staleFallbackEnabled", cachePolicy.staleFallbackEnabled)
                put("staleFallbackSeconds", cachePolicy.staleFallbackSeconds)
                put("negativeTtlEnabled", cachePolicy.negativeTtlEnabled)
                put("negativeTtlSeconds", cachePolicy.negativeTtlSeconds)
            })
            put("providers", JSONArray().apply {
                put(JSONObject().apply {
                    put("id", upstream.id)
                    put("protocol", when (upstream.protocol) {
                        DnsModeProtocol.DNS -> "PLAIN"
                        DnsModeProtocol.DOH -> "DOH"
                        DnsModeProtocol.DOT -> "DOT"
                    })
                    put("server", when (upstream.protocol) {
                        DnsModeProtocol.DNS, DnsModeProtocol.DOT -> {
                            val addr = upstream.address
                            val p = upstream.port
                            if (addr.contains(':') && !addr.startsWith('[')) "[$addr]:$p" else "$addr:$p"
                        }
                        DnsModeProtocol.DOH -> ""
                    })
                    put("url", if (upstream.protocol == DnsModeProtocol.DOH) upstream.address else "")
                })
            })
            put("bootstrap", JSONObject().apply {
                put("enabled", false)
                put("ips", JSONArray())
            })
        }.toString()

        runCatching {
            engine.applyDNSConfig(json)
        }.onFailure { Log.e(TAG, "Failed to apply DNS config to Go engine", it) }
    }

    /**
     * Executes a DNS query against the running standalone server for diagnostics or testing.
     */
    fun processQuery(queryBytes: ByteArray, timeoutMs: Int = 2000): ByteArray? {
        if (!isRunning) return null
        return try {
            val socket = DatagramSocket()
            socket.soTimeout = timeoutMs
            val sendPacket = DatagramPacket(
                queryBytes,
                queryBytes.size,
                InetAddress.getByName("127.0.0.1"),
                config.localListenPort
            )
            socket.send(sendPacket)
            val recvBuf = ByteArray(4096)
            val recvPacket = DatagramPacket(recvBuf, recvBuf.size)
            socket.receive(recvPacket)
            socket.close()
            recvBuf.copyOf(recvPacket.length)
        } catch (e: Exception) {
            Log.w(TAG, "processQuery failed: ${e.message}")
            null
        }
    }

    companion object {
        private const val TAG = "DnsServerEngine"
    }
}
