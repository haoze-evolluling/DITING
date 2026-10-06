package com.haoze.diting.express

import com.haoze.diting.express.engine.ExpressDnsEngine
import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.express.engine.ExpressUpstreamDispatcher
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.DnsProvider
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

class ExpressDnsEngineTest {

    private val provider1 = DnsProvider(
        id = "p1",
        name = "Test Provider 1",
        protocol = DnsProtocol.DNS,
        host = "8.8.8.8",
        port = 53
    )

    private class FakeCache : ExpressDnsEngine.ExpressDnsCache {
        val map = ConcurrentHashMap<String, ByteArray>()
        override suspend fun get(question: ExpressDnsMessageUtils.DnsQuestion, requestQuery: ByteArray): ByteArray? {
            return map[question.name]
        }
        override suspend fun put(question: ExpressDnsMessageUtils.DnsQuestion, response: ByteArray) {
            map[question.name] = response
        }
    }

    @Test
    fun testDdrMitigation() = runBlocking {
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            activeProvidersProvider = { listOf(provider1) }
        )

        val query = ExpressDnsMessageUtils.buildQuery("_dns.resolver.arpa", ExpressDnsMessageUtils.TYPE_A)
        val resp = engine.resolve(query)
        assertEquals(ExpressDnsMessageUtils.RCODE_NXDOMAIN, ExpressDnsMessageUtils.responseCode(resp))
        assertEquals(1, engine.stats.blockedQueries.get())
    }

    @Test
    fun testRuleEvaluationBlocking() = runBlocking {
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            ruleEvaluator = { domain, _ ->
                if (domain.contains("tracker")) {
                    ExpressDnsEngine.RuleEvaluation(blocked = true, reason = "tracker_block")
                } else {
                    ExpressDnsEngine.RuleEvaluation(blocked = false)
                }
            },
            blockResponseModeProvider = { BlockResponseMode.REFUSED },
            activeProvidersProvider = { listOf(provider1) }
        )

        // Blocked domain
        val blockedQuery = ExpressDnsMessageUtils.buildQuery("analytics.tracker.com", ExpressDnsMessageUtils.TYPE_A)
        val blockedResp = engine.resolve(blockedQuery)
        assertEquals(ExpressDnsMessageUtils.RCODE_REFUSED, ExpressDnsMessageUtils.responseCode(blockedResp))
        assertEquals(1, engine.stats.blockedQueries.get())

        // Allowed domain
        val allowedQuery = ExpressDnsMessageUtils.buildQuery("google.com", ExpressDnsMessageUtils.TYPE_A)
        val allowedResp = engine.resolve(allowedQuery)
        assertEquals(ExpressDnsMessageUtils.RCODE_NOERROR, ExpressDnsMessageUtils.responseCode(allowedResp))
        assertEquals(1, engine.stats.blockedQueries.get())
        assertEquals(2, engine.stats.totalQueries.get())
    }

    @Test
    fun testNonAddressTypesBypassRules() = runBlocking {
        var ruleCalled = false
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            ruleEvaluator = { _, _ ->
                ruleCalled = true
                ExpressDnsEngine.RuleEvaluation(blocked = true)
            },
            activeProvidersProvider = { listOf(provider1) }
        )

        // Type 16 = TXT
        val txtQuery = ExpressDnsMessageUtils.buildQuery("test.com", 16)
        val resp = engine.resolve(txtQuery)
        // Rule evaluator should NOT be called for TXT
        org.junit.Assert.assertFalse(ruleCalled)
        assertNotNull(resp)
    }

    @Test
    fun testCacheHitAndMiss() = runBlocking {
        val cache = FakeCache()
        var upstreamCount = 0

        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                upstreamCount++
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            cache = cache,
            activeProvidersProvider = { listOf(provider1) }
        )

        val q1 = ExpressDnsMessageUtils.buildQuery("cached.org", ExpressDnsMessageUtils.TYPE_A, 0x1111)
        val resp1 = engine.resolve(q1)
        assertEquals(1, upstreamCount)
        assertEquals(0, engine.stats.cacheHits.get())
        assertEquals(0x1111, ExpressDnsMessageUtils.transactionId(resp1))

        // Second query with different transaction ID should hit cache and adopt new tx ID
        val q2 = ExpressDnsMessageUtils.buildQuery("cached.org", ExpressDnsMessageUtils.TYPE_A, 0x2222)
        val resp2 = engine.resolve(q2)
        assertEquals(1, upstreamCount) // Upstream not called
        assertEquals(1, engine.stats.cacheHits.get())
        assertEquals(0x2222, ExpressDnsMessageUtils.transactionId(resp2))
    }

    @Test
    fun testUpstreamFailureReturnsServfail() = runBlocking {
        var loggedReason: String? = null
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, _, _, _ ->
                throw java.io.IOException("Network unreachable")
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            activeProvidersProvider = { listOf(provider1) },
            dnsLogger = { _, _, _, reason, _, _, _, _ ->
                loggedReason = reason
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("failed.upstream.com", ExpressDnsMessageUtils.TYPE_A, 0x4444)
        val resp = engine.resolve(query)
        assertEquals(ExpressDnsMessageUtils.RCODE_SERVFAIL, ExpressDnsMessageUtils.responseCode(resp))
        assertEquals(0x4444, ExpressDnsMessageUtils.transactionId(resp))
        assertEquals(1, engine.stats.totalQueries.get())
        assertTrue(loggedReason?.contains("Network unreachable") == true)
    }

    @Test
    fun testTruncatedResponseNotCached() = runBlocking {
        val cache = FakeCache()
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                val base = ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
                base[2] = (base[2].toInt() or 0x02).toByte() // Set TC flag (Truncated)
                base
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            cache = cache,
            activeProvidersProvider = { listOf(provider1) }
        )

        val q = ExpressDnsMessageUtils.buildQuery("truncated.com", ExpressDnsMessageUtils.TYPE_A)
        val resp = engine.resolve(q)
        assertTrue(ExpressDnsMessageUtils.isTruncatedResponse(resp))
        assertTrue(cache.map.isEmpty())
    }

    @Test
    fun testRuleEvaluationBlockingPassesSubscriptionId() = runBlocking {
        var loggedBlocked: Boolean? = null
        var loggedSubscriptionId: Long? = null
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val engine = ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            ruleEvaluator = { domain, _ ->
                if (domain == "ad.example.com") {
                    ExpressDnsEngine.RuleEvaluation(
                        blocked = true,
                        reason = "||ad.example.com^",
                        blockSubscriptionId = 42L
                    )
                } else {
                    ExpressDnsEngine.RuleEvaluation(blocked = false)
                }
            },
            blockResponseModeProvider = { BlockResponseMode.NXDOMAIN },
            activeProvidersProvider = { listOf(provider1) },
            dnsLogger = { _, _, blocked, _, _, _, _, blockSubId ->
                loggedBlocked = blocked
                loggedSubscriptionId = blockSubId
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("ad.example.com", ExpressDnsMessageUtils.TYPE_A)
        val resp = engine.resolve(query)
        assertEquals(ExpressDnsMessageUtils.RCODE_NXDOMAIN, ExpressDnsMessageUtils.responseCode(resp))
        assertEquals(true, loggedBlocked)
        assertEquals(42L, loggedSubscriptionId)
    }
}

