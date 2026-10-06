package com.haoze.diting.express

import com.haoze.diting.express.dns.ExpressDnsMessageUtils
import com.haoze.diting.express.engine.ExpressUpstreamDispatcher
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.core.rule.BlockResponseMode
import com.haoze.diting.core.dns.DnsProtocol
import com.haoze.diting.core.dns.DnsProvider
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.Closeable
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

class ExpressUpstreamDispatcherTest {

    private val providerA = DnsProvider(id = "pA", name = "Fast", protocol = DnsProtocol.DNS, host = "1.1.1.1", port = 53)
    private val providerB = DnsProvider(id = "pB", name = "Slow", protocol = DnsProtocol.DNS, host = "8.8.8.8", port = 53)

    @Test
    fun testSingleMode() = runBlocking {
        var calledProviderId = ""
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { p, query, _, _ ->
                calledProviderId = p.id
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("single.test", ExpressDnsMessageUtils.TYPE_A)
        val resp = dispatcher.dispatch(DnsResolutionMode.SINGLE, listOf(providerA, providerB), query)
        assertNotNull(resp)
        assertEquals("pA", calledProviderId)
    }

    @Test
    fun testPrimaryBackupFailover() = runBlocking {
        val attempts = mutableListOf<String>()
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { p, query, _, _ ->
                attempts.add(p.id)
                if (p.id == "pA") {
                    throw IOException("Provider A unreachable")
                }
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("failover.test", ExpressDnsMessageUtils.TYPE_A)
        val resp = dispatcher.dispatch(DnsResolutionMode.PRIMARY_BACKUP, listOf(providerA, providerB), query)
        assertNotNull(resp)
        assertEquals(listOf("pA", "pB"), attempts)
    }

    @Test
    fun testParallelRaceWinnerAndSocketCancellation() = runBlocking {
        val slowSocketClosed = AtomicBoolean(false)
        val slowSocket = Closeable { slowSocketClosed.set(true) }

        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { p, query, _, onActive ->
                if (p.id == "pB") { // slow
                    onActive?.invoke(slowSocket)
                    delay(500)
                    ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
                } else { // fast
                    delay(20)
                    ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
                }
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("race.test", ExpressDnsMessageUtils.TYPE_A)
        val resp = dispatcher.dispatch(DnsResolutionMode.PARALLEL_RACE, listOf(providerA, providerB), query)
        assertNotNull(resp)

        // Wait brief moment for cancellation cleanup to run
        delay(50)
        assertTrue("Slow socket should be closed upon race cancellation", slowSocketClosed.get())
    }

    @Test
    fun testSmartPredictionMode() = runBlocking {
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )
        val query = ExpressDnsMessageUtils.buildQuery("smart.test", ExpressDnsMessageUtils.TYPE_A)
        val resp = dispatcher.dispatch(DnsResolutionMode.SMART_PREDICTION, listOf(providerA), query)
        assertNotNull(resp)
    }

    @Test
    fun testPrimaryBackupFailoverOnServfail() = runBlocking {
        val attempts = mutableListOf<String>()
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { p, query, _, _ ->
                attempts.add(p.id)
                if (p.id == "pA") {
                    ExpressDnsMessageUtils.buildServfailResponse(query)
                } else {
                    ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
                }
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("servfail-failover.test", ExpressDnsMessageUtils.TYPE_A)
        val resp = dispatcher.dispatch(DnsResolutionMode.PRIMARY_BACKUP, listOf(providerA, providerB), query)
        assertNotNull(resp)
        assertEquals(ExpressDnsMessageUtils.RCODE_NOERROR, ExpressDnsMessageUtils.responseCode(resp))
        assertEquals(listOf("pA", "pB"), attempts)
    }

    @Test
    fun testParallelRaceIgnoresFastServfail() = runBlocking {
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { p, query, _, _ ->
                if (p.id == "pA") {
                    delay(10)
                    ExpressDnsMessageUtils.buildServfailResponse(query)
                } else {
                    delay(50)
                    ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
                }
            }
        )

        val query = ExpressDnsMessageUtils.buildQuery("race-servfail.test", ExpressDnsMessageUtils.TYPE_A)
        val resp = dispatcher.dispatch(DnsResolutionMode.PARALLEL_RACE, listOf(providerA, providerB), query)
        assertNotNull(resp)
        assertEquals(ExpressDnsMessageUtils.RCODE_NOERROR, ExpressDnsMessageUtils.responseCode(resp))
    }
}
