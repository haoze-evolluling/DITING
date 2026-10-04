package com.haoze.diting.dnsmode

import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.backend.DnsModePreferences
import com.haoze.diting.dnsmode.model.DnsListenPortValidator
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.dnsmode.model.DnsUpstreamValidator
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

class DnsModeTest {

    companion object {
        private val isNativeAvailable: Boolean by lazy {
            try {
                tunnel.Engine()
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    @Before
    fun setUp() {
        DnsModeManager.onServiceStopped()
        DnsModeManager.resetStats()
    }

    @Test
    fun `DnsModeProtocol has correct properties and default ports`() {
        assertEquals("DNS", DnsModeProtocol.DNS.label)
        assertEquals(53, DnsModeProtocol.DNS.defaultPort)

        assertEquals("DoH", DnsModeProtocol.DOH.label)
        assertEquals(443, DnsModeProtocol.DOH.defaultPort)

        assertEquals("DoT", DnsModeProtocol.DOT.label)
        assertEquals(853, DnsModeProtocol.DOT.defaultPort)

        assertEquals(DnsModeProtocol.DNS, DnsModeProtocol.fromStorage("DNS"))
        assertEquals(DnsModeProtocol.DNS, DnsModeProtocol.fromStorage("dns"))
        assertEquals(DnsModeProtocol.DOH, DnsModeProtocol.fromStorage("DOH"))
        assertEquals(DnsModeProtocol.DOT, DnsModeProtocol.fromStorage("DOT"))
        assertEquals(DnsModeProtocol.DNS, DnsModeProtocol.fromStorage("UNKNOWN"))
    }

    @Test
    fun `DnsUpstreamServer presets contain dns doh and dot endpoints`() {
        val presets = DnsUpstreamServer.PRESETS
        assertEquals(18, presets.size)
        assertEquals("preset_alidns_dns", presets.first().id)
        assertEquals("阿里云", presets.first().name)
        assertEquals("1.1.1.1", presets.firstOrNull { it.id == "preset_cloudflare_dns" }?.address)

        val dohServer = presets.firstOrNull { it.protocol == DnsModeProtocol.DOH }
        assertNotNull(dohServer)
        assertTrue(dohServer?.address?.startsWith("https://") == true)
        assertEquals("[DoH] ${dohServer?.address}", dohServer?.endpointLabel())

        val dotServer = presets.firstOrNull { it.protocol == DnsModeProtocol.DOT }
        assertNotNull(dotServer)
        assertEquals(853, dotServer?.port)
        assertEquals("[DoT] ${dotServer?.address}:${dotServer?.port}", dotServer?.endpointLabel())
    }

    @Test
    fun `DnsServiceStatus isRunning resolves accurately`() {
        assertTrue(DnsServiceStatus.RUNNING.isRunning)
        assertFalse(DnsServiceStatus.STOPPED.isRunning)
        assertFalse(DnsServiceStatus.STARTING.isRunning)
        assertFalse(DnsServiceStatus.STOPPING.isRunning)
        assertFalse(DnsServiceStatus.ERROR.isRunning)
    }

    @Test
    fun `DnsModeStats tracks query counts and latencies properly`() {
        assertEquals(0L, DnsModeManager.stats.value.queryCount)
        assertEquals(0L, DnsModeManager.stats.value.cacheHitCount)
        assertEquals(0L, DnsModeManager.stats.value.blockedCount)

        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = false, latencyMs = 20L)
        assertEquals(1L, DnsModeManager.stats.value.queryCount)
        assertEquals(0L, DnsModeManager.stats.value.cacheHitCount)
        assertEquals(20L, DnsModeManager.stats.value.latencyMs)

        DnsModeManager.recordQuery(cacheHit = true, blocked = false, failed = false, latencyMs = 5L)
        assertEquals(2L, DnsModeManager.stats.value.queryCount)
        assertEquals(1L, DnsModeManager.stats.value.cacheHitCount)
        // Average latency: (20 + 5) / 2
        assertEquals(12L, DnsModeManager.stats.value.latencyMs)

        DnsModeManager.recordQuery(cacheHit = false, blocked = true, failed = false, latencyMs = 1L)
        assertEquals(3L, DnsModeManager.stats.value.queryCount)
        assertEquals(1L, DnsModeManager.stats.value.cacheHitCount)
        assertEquals(1L, DnsModeManager.stats.value.blockedCount)
        // Average latency: (20 + 5 + 1) / 3
        assertEquals(8L, DnsModeManager.stats.value.latencyMs)

        DnsModeManager.resetStats()
        assertEquals(0L, DnsModeManager.stats.value.queryCount)
        assertEquals(0L, DnsModeManager.stats.value.cacheHitCount)
        assertEquals(0L, DnsModeManager.stats.value.blockedCount)
    }

    @Test
    fun `failed queries count but do not skew average latency`() {
        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = false, latencyMs = 10L)
        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = false, latencyMs = 20L)
        // A SERVFAIL timeout must not drag the reported latency up
        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = true, latencyMs = 9000L)

        assertEquals(3L, DnsModeManager.stats.value.queryCount)
        assertEquals(1L, DnsModeManager.stats.value.failedCount)
        assertEquals(0L, DnsModeManager.stats.value.blockedCount)
        // Average latency over successful answers only: (10 + 20) / 2
        assertEquals(15L, DnsModeManager.stats.value.latencyMs)

        // Only-failure run must not divide by zero
        DnsModeManager.resetStats()
        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = true, latencyMs = 9000L)
        assertEquals(1L, DnsModeManager.stats.value.queryCount)
        assertEquals(0L, DnsModeManager.stats.value.latencyMs)
    }

    @Test
    fun `onServiceStarted resets stats only on a fresh start`() {
        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = false, latencyMs = 10L)
        // Fresh start (STOPPED -> RUNNING) wipes the previous run's counters
        DnsModeManager.onServiceStarted()
        assertEquals(0L, DnsModeManager.stats.value.queryCount)

        DnsModeManager.recordQuery(cacheHit = false, blocked = false, failed = false, latencyMs = 10L)
        // Idempotent resync while RUNNING keeps the ongoing run's stats
        DnsModeManager.onServiceStarted()
        assertEquals(1L, DnsModeManager.stats.value.queryCount)

        DnsModeManager.onServiceStopped()
        assertEquals(DnsServiceStatus.STOPPED, DnsModeManager.status.value)
    }

    @Test
    fun `DnsModeManager service lifecycle callbacks transition status`() {
        assertEquals(DnsServiceStatus.STOPPED, DnsModeManager.status.value)

        DnsModeManager.onServiceStarted()
        assertEquals(DnsServiceStatus.RUNNING, DnsModeManager.status.value)
        assertTrue(DnsModeManager.status.value.isRunning)

        DnsModeManager.onServiceStopped()
        assertEquals(DnsServiceStatus.STOPPED, DnsModeManager.status.value)
        assertFalse(DnsModeManager.status.value.isRunning)

        DnsModeManager.onServiceError("DNS 服务启动失败")
        assertEquals(DnsServiceStatus.ERROR, DnsModeManager.status.value)
    }

    @Test
    fun `ERROR status survives service destroy notification`() {
        DnsModeManager.onServiceError("DNS 服务启动失败，监听端口可能被占用")
        // onDestroy always fires onServiceStopped; it must not mask the error state
        DnsModeManager.onServiceStopped()
        assertEquals(DnsServiceStatus.ERROR, DnsModeManager.status.value)
        assertEquals("DNS 服务启动失败，监听端口可能被占用", DnsModeManager.errorReason.value)

        DnsModeManager.onServiceStarted()
        assertEquals(DnsServiceStatus.RUNNING, DnsModeManager.status.value)
        assertEquals(null, DnsModeManager.errorReason.value)
        DnsModeManager.onServiceStopped()
        assertEquals(DnsServiceStatus.STOPPED, DnsModeManager.status.value)
    }

    @Test
    fun `DnsModeConfig default values are reasonable`() {
        val config = DnsModeConfig()
        assertEquals("preset_alidns_dns", config.selectedUpstreamId)
        assertEquals(1053, config.localListenPort)
        assertTrue(config.cacheEnabled)
        assertEquals(300, config.cacheTtlSeconds)
        assertFalse(config.adBlockEnabled)
        assertFalse(config.logQueries)
    }

    @Test
    fun `DnsUpstreamValidator accepts valid inputs and rejects invalid ones`() {
        val validator = DnsUpstreamValidator

        assertNull(validator.validateName("自定义 DNS"))
        assertNotNull(validator.validateName("   "))

        assertNull(validator.validateAddress(DnsModeProtocol.DNS, "223.5.5.5"))
        assertNull(validator.validateAddress(DnsModeProtocol.DNS, "2001:db8::1"))
        assertNull(validator.validateAddress(DnsModeProtocol.DOT, "dns.alidns.com"))
        assertNull(validator.validateAddress(DnsModeProtocol.DOH, "https://dns.alidns.com/dns-query"))
        assertNotNull(validator.validateAddress(DnsModeProtocol.DOH, "http://dns.alidns.com/dns-query"))
        assertNotNull(validator.validateAddress(DnsModeProtocol.DNS, ""))
        assertNotNull(validator.validateAddress(DnsModeProtocol.DNS, "1 1 1 1"))

        assertNull(validator.validatePort("", DnsModeProtocol.DNS))
        assertNull(validator.validatePort("853", DnsModeProtocol.DOT))
        assertNotNull(validator.validatePort("0", DnsModeProtocol.DNS))
        assertNotNull(validator.validatePort("70000", DnsModeProtocol.DNS))
        assertNotNull(validator.validatePort("abc", DnsModeProtocol.DNS))
        assertNull(validator.validatePort("abc", DnsModeProtocol.DOH))

        assertEquals(53, validator.parsePort("", DnsModeProtocol.DNS))
        assertEquals(853, validator.parsePort("853", DnsModeProtocol.DOT))
    }

    @Test
    fun `custom upstream serialization round trips`() {
        val servers = listOf(
            DnsUpstreamServer(
                id = "custom_1",
                name = "自定义 DoH",
                address = "https://example.com/dns-query",
                port = 443,
                protocol = DnsModeProtocol.DOH,
                isCustom = true
            ),
            DnsUpstreamServer(
                id = "custom_2",
                name = "自定义 DNS",
                address = "192.168.1.2",
                port = 5335,
                protocol = DnsModeProtocol.DNS,
                isCustom = true
            )
        )
        val json = DnsModePreferences.serializeUpstreams(servers)
        assertEquals(servers, DnsModePreferences.deserializeUpstreams(json))

        assertEquals(emptyList<DnsUpstreamServer>(), DnsModePreferences.deserializeUpstreams(null))
        assertEquals(emptyList<DnsUpstreamServer>(), DnsModePreferences.deserializeUpstreams(""))
        assertEquals(emptyList<DnsUpstreamServer>(), DnsModePreferences.deserializeUpstreams("not json"))
    }

    @Test
    fun `DnsServerEngine starts and stops cleanly`() {
        assumeTrue("Skipping native Go engine test on host JVM without gojni", isNativeAvailable)
        val config = DnsModeConfig(localListenPort = 15354)
        val upstream = DnsUpstreamServer.PRESETS.first()
        val engine = com.haoze.diting.dnsmode.backend.DnsServerEngine(config, upstream)
        val started = engine.start()
        assertTrue(started)
        engine.stop()
    }

    @Test
    fun `DnsServerEngine answers SERVFAIL when upstream is unreachable`() {
        assumeTrue("Skipping native Go engine test on host JVM without gojni", isNativeAvailable)
        val config = DnsModeConfig(localListenPort = 15355, cacheEnabled = false)
        // Nothing listens on port 1; the query must fail into a SERVFAIL
        // response (rcode 2), not a policy REFUSED (rcode 5).
        val upstream = DnsUpstreamServer(
            id = "unreachable",
            name = "Unreachable",
            address = "127.0.0.1",
            port = 1,
            protocol = DnsModeProtocol.DNS
        )
        val engine = com.haoze.diting.dnsmode.backend.DnsServerEngine(config, upstream)
        assertTrue(engine.start())
        try {
            val query = com.haoze.diting.vpn.DnsMessageUtils.buildQuery("example.com", 1)
            val response = engine.processQuery(query)
            assertNotNull(response)
            assertEquals(2, com.haoze.diting.vpn.DnsMessageUtils.responseCode(response!!))
        } finally {
            engine.stop()
        }
    }

    @Test
    fun `getActiveUpstream falls back gracefully when id is unknown`() {
        // Unknown id should fall back to first preset
        val upstream = DnsModeManager.getActiveUpstream()
        assertNotNull(upstream)
        assertEquals("preset_alidns_dns", upstream.id)
    }

    @Test
    fun `DnsListenPortValidator accepts editable range and rejects others`() {
        assertNull(DnsListenPortValidator.validate("1053"))
        assertNull(DnsListenPortValidator.validate("5353"))
        assertNull(DnsListenPortValidator.validate("65535"))
        assertNull(DnsListenPortValidator.validate("1024"))

        assertNotNull(DnsListenPortValidator.validate("abc"))
        assertNotNull(DnsListenPortValidator.validate(""))
        assertNotNull(DnsListenPortValidator.validate("53"))
        assertNotNull(DnsListenPortValidator.validate("1023"))
        assertNotNull(DnsListenPortValidator.validate("65536"))

        assertEquals(1053, DnsListenPortValidator.DEFAULT_PORT)
        assertEquals(1053, DnsListenPortValidator.parse("1053"))
    }
}
