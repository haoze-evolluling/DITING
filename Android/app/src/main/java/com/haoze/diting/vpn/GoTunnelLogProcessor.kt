package com.haoze.diting.vpn

import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.vpn.cache.DnsResponseCache
import org.json.JSONArray

/**
 * Handles decoding, rule attribution, and dispatching of DNS batch logs
 * and HTTP inspection logs produced by the Go engine.
 */
internal class GoTunnelLogProcessor(
    private val dnsPolicy: DomainPolicy,
    private val dnsLogger: DnsLogger,
    private val dnsCache: DnsResponseCache
) {

    suspend fun processLogBatch(jsonLogs: String) {
        val array = runCatching { JSONArray(jsonLogs) }.getOrNull() ?: return
        val len = array.length()
        if (len == 0) return

        val entities = ArrayList<DnsLogEntity>(len)
        for (i in 0 until len) {
            val obj = array.optJSONObject(i) ?: continue
            val domain = obj.optString("d")
            val blocked = obj.optBoolean("b")
            val queryType = obj.optInt("t")
            val responseTimeMs = obj.optLong("r")
            val appName = obj.optString("a")
            val resolvedIPs = obj.optString("i")
            val blockedBy = obj.optString("k")
            val errorMessage = obj.optString("e")
            val cached = obj.optBoolean("c")
            val timestamp = obj.optLong("ts").takeIf { it > 0 } ?: System.currentTimeMillis()
            val ttl = obj.optLong("ttl", 0L)

            val result = when {
                errorMessage.isNotBlank() -> LogResult.ERROR
                blockedBy.startsWith("rewrite=") -> LogResult.REWRITTEN
                blocked -> LogResult.BLOCKED
                else -> LogResult.PASSED
            }
            val effectivePackage = appName.ifBlank { null }
            val effectiveBlockedBy: String
            val blockSubId: Long?
            val isConnectionLog = blockedBy == "connection"

            if (result == LogResult.BLOCKED) {
                val decision = dnsPolicy.evaluate(domain, effectivePackage)
                val ruleTypeTag = if (decision.isAppSpecific) "app rule" else if (decision.matchedRule != null) "global rule" else null
                effectiveBlockedBy = if (ruleTypeTag != null && blockedBy.isNotBlank()) "$blockedBy ($ruleTypeTag)" else (ruleTypeTag ?: blockedBy)
                blockSubId = (decision as? DomainDecision.Block)?.source?.subscriptionIdOrNull()
                    ?: parseBlockSubscriptionIdFromToken(blockedBy)
            } else if (blockedBy.startsWith("rewrite=")) {
                effectiveBlockedBy = blockedBy
                blockSubId = null
            } else if (isConnectionLog) {
                effectiveBlockedBy = "connection"
                blockSubId = null
            } else {
                effectiveBlockedBy = ""
                blockSubId = null
            }

            if (dnsLogger.isLoggable(result)) {
                entities.add(
                    DnsLogEntity(
                        timestamp = timestamp,
                        queryName = domain.lowercase(),
                        queryType = queryType,
                        result = result.value,
                        message = buildDnsLogMessage(appName, resolvedIPs, effectiveBlockedBy, errorMessage, responseTimeMs),
                        cached = cached,
                        blockSubscriptionId = blockSubId,
                        packageName = effectivePackage
                    )
                )
            }

            if (result == LogResult.PASSED && !isConnectionLog) {
                if (cached) {
                    dnsCache.recordCacheHit(domain, queryType)
                } else if (resolvedIPs.isNotBlank()) {
                    dnsCache.recordResolved(domain, queryType, resolvedIPs, upstreamTtl = ttl)
                }

            }
        }

        if (entities.isNotEmpty()) {
            dnsLogger.logBatch(entities)
        }
    }

    fun resolveHttpBlockSubscriptionId(
        authority: String,
        outcome: HttpRequestOutcome,
        packageName: String? = null
    ): Long? {
        if (outcome != HttpRequestOutcome.BLOCKED) return null
        return resolveBlockSubscriptionId(authority, packageName)
    }

    fun resolveBlockSubscriptionId(authority: String, packageName: String? = null): Long? {
        if (authority.isBlank()) return null
        val source = (dnsPolicy.evaluate(authority, packageName) as? DomainDecision.Block)?.source ?: return null
        return source.subscriptionIdOrNull()
    }

    private fun parseBlockSubscriptionIdFromToken(blockedBy: String): Long? {
        return blockedBy
            .split(',')
            .map { it.trim() }
            .firstNotNullOfOrNull { token ->
                if (token.startsWith("sub_")) token.removePrefix("sub_").toLongOrNull() else null
            }
    }

    private fun buildDnsLogMessage(
        appName: String,
        resolvedIPs: String,
        blockedBy: String,
        errorMessage: String,
        responseTimeMs: Long
    ): String? = listOfNotNull(
        appName.takeIf { it.isNotBlank() }?.let { "app=$it" },
        resolvedIPs.takeIf { it.isNotBlank() }?.let { "resolved=$it" },
        blockedBy.takeIf { it.isNotBlank() }?.let { "blocked_by=$it" },
        errorMessage.takeIf { it.isNotBlank() }?.let { "error=$it" },
        responseTimeMs.takeIf { it > 0 }?.let { "elapsed=${it}ms" }
    ).joinToString(", ").takeIf { it.isNotEmpty() }
}

internal fun String.subscriptionIdOrNull(): Long? =
    if (startsWith("sub_")) removePrefix("sub_").toLongOrNull() else null

internal fun String.toHttpRequestOutcome(): HttpRequestOutcome = when (this) {
    "blocked" -> HttpRequestOutcome.BLOCKED
    "rewritten" -> HttpRequestOutcome.REWRITTEN
    "passthrough" -> HttpRequestOutcome.PASSTHROUGH
    "handshake_failed" -> HttpRequestOutcome.HANDSHAKE_FAILED
    "upstream_failed" -> HttpRequestOutcome.UPSTREAM_FAILED
    "decryption_failed" -> HttpRequestOutcome.DECRYPTION_FAILED
    "invalid" -> HttpRequestOutcome.INVALID
    "error" -> HttpRequestOutcome.ERROR
    else -> HttpRequestOutcome.ALLOWED
}
