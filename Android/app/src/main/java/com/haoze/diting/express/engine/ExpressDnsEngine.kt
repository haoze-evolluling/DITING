package com.haoze.diting.express.engine

import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.DnsProvider
import java.util.concurrent.atomic.AtomicLong

/**
 * Core DNS query processing pipeline for Express Mode.
 *
 * Execution sequence (aligned with tunnel/engine_dns.go):
 * 1. DDR counter-measure (_dns.resolver.arpa -> NXDOMAIN)
 * 2. Domain rules filtering (A/AAAA only, evaluated via injected ruleEvaluator)
 * 3. Block response synthesis via BlockResponseMode & ExpressDnsMessageUtils
 * 4. Persistent cache query
 * 5. Upstream dispatch via ExpressUpstreamDispatcher
 *
 * Fully JVM testable with zero android.* imports.
 */
class ExpressDnsEngine(
    private val upstreamDispatcher: ExpressUpstreamDispatcher,
    private val ruleEvaluator: ExpressRuleEvaluator? = null,
    private val cache: ExpressDnsCache? = null,
    private val isDomainRulesEnabledProvider: () -> Boolean = { true },
    private val blockResponseModeProvider: () -> BlockResponseMode = { BlockResponseMode.NXDOMAIN },
    private val activeProvidersProvider: () -> List<DnsProvider>,
    private val resolutionModeProvider: () -> DnsResolutionMode = { DnsResolutionMode.SINGLE },
    private val dnsLogger: ExpressDnsLogger? = null
) {

    data class RuleEvaluation(
        val blocked: Boolean,
        val reason: String? = null
    )

    fun interface ExpressRuleEvaluator {
        suspend fun evaluate(domain: String, queryType: Int): RuleEvaluation
    }

    interface ExpressDnsCache {
        suspend fun get(question: ExpressDnsMessageUtils.DnsQuestion, requestQuery: ByteArray): ByteArray?
        suspend fun put(question: ExpressDnsMessageUtils.DnsQuestion, response: ByteArray)
    }

    fun interface ExpressDnsLogger {
        fun logQuery(
            domain: String,
            queryType: Int,
            blocked: Boolean,
            reason: String?,
            cached: Boolean,
            latencyMs: Long,
            providerName: String?
        )
    }

    class EngineStats {
        val totalQueries = AtomicLong(0)
        val blockedQueries = AtomicLong(0)
        val cacheHits = AtomicLong(0)
        val upstreamQueries = AtomicLong(0)
        val totalLatencyMs = AtomicLong(0)

        val averageLatencyMs: Double
            get() {
                val total = totalQueries.get()
                return if (total > 0) totalLatencyMs.get().toDouble() / total else 0.0
            }
    }

    val stats = EngineStats()

    suspend fun resolve(query: ByteArray): ByteArray {
        val startNs = System.nanoTime()
        val question = ExpressDnsMessageUtils.extractQuestion(query)
            ?: return ExpressDnsMessageUtils.buildServfailResponse(query)

        val domain = question.name
        val queryType = question.type

        // 1. DDR Mitigation (RFC 9462): Return NXDOMAIN for _dns.resolver.arpa to prevent encrypted bypass
        if (domain == "_dns.resolver.arpa" || domain.endsWith("._dns.resolver.arpa")) {
            val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
            stats.totalQueries.incrementAndGet()
            stats.blockedQueries.incrementAndGet()
            stats.totalLatencyMs.addAndGet(elapsedMs)
            dnsLogger?.logQuery(domain, queryType, blocked = true, reason = "ddr_mitigation", cached = false, latencyMs = elapsedMs, providerName = null)
            return ExpressDnsMessageUtils.buildNegativeResponse(query, ExpressDnsMessageUtils.RCODE_NXDOMAIN)
        }

        // 2. Domain rules filtering (A/AAAA only; other query types forward as-is)
        val isAddressQuery = queryType == ExpressDnsMessageUtils.TYPE_A || queryType == ExpressDnsMessageUtils.TYPE_AAAA
        if (isAddressQuery && isDomainRulesEnabledProvider() && ruleEvaluator != null) {
            val evaluation = ruleEvaluator.evaluate(domain, queryType)
            if (evaluation.blocked) {
                val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
                stats.totalQueries.incrementAndGet()
                stats.blockedQueries.incrementAndGet()
                stats.totalLatencyMs.addAndGet(elapsedMs)
                val blockMode = blockResponseModeProvider()
                val blockResp = ExpressDnsMessageUtils.buildBlockedResponse(query, blockMode)
                dnsLogger?.logQuery(domain, queryType, blocked = true, reason = evaluation.reason ?: "blocked", cached = false, latencyMs = elapsedMs, providerName = null)
                return blockResp
            }
        }

        // 3. DNS Cache lookup
        if (cache != null) {
            val cachedResponse = cache.get(question, query)
            if (cachedResponse != null) {
                val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
                stats.totalQueries.incrementAndGet()
                stats.cacheHits.incrementAndGet()
                stats.totalLatencyMs.addAndGet(elapsedMs)
                val patched = ExpressDnsMessageUtils.withTransactionId(cachedResponse, query)
                dnsLogger?.logQuery(domain, queryType, blocked = false, reason = null, cached = true, latencyMs = elapsedMs, providerName = "cache")
                return patched
            }
        }

        // 4. Upstream dispatch
        stats.upstreamQueries.incrementAndGet()
        val providers = activeProvidersProvider()
        val mode = resolutionModeProvider()
        val response = try {
            if (providers.isEmpty()) {
                throw java.io.IOException("No active upstream DNS providers configured")
            }
            upstreamDispatcher.dispatch(mode, providers, query, question)
        } catch (e: Exception) {
            val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
            stats.totalQueries.incrementAndGet()
            stats.totalLatencyMs.addAndGet(elapsedMs)
            dnsLogger?.logQuery(domain, queryType, blocked = false, reason = "upstream_failure: ${e.message}", cached = false, latencyMs = elapsedMs, providerName = null)
            return ExpressDnsMessageUtils.buildServfailResponse(query)
        }

        val elapsedMs = (System.nanoTime() - startNs) / 1_000_000
        stats.totalQueries.incrementAndGet()
        stats.totalLatencyMs.addAndGet(elapsedMs)

        if (ExpressDnsMessageUtils.isSuccessResponse(response) && !ExpressDnsMessageUtils.isTruncatedResponse(response)) {
            cache?.put(question, response)
        }

        dnsLogger?.logQuery(domain, queryType, blocked = false, reason = null, cached = false, latencyMs = elapsedMs, providerName = providers.firstOrNull()?.name)
        return response
    }
}
