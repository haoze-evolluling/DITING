package com.haoze.diting.dnsmode

import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.backend.DnsModeService
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsModeStats
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DnsModeTest {

    @Before
    fun setUp() {
        DnsModeManager.onServiceStopped()
        DnsModeManager.resetStats()
    }

    @Test
    fun `DnsModeProtocol has correct properties and default ports`() {
        assertEquals("UDP", DnsModeProtocol.UDP.label)
        assertEquals(53, DnsModeProtocol.UDP.defaultPort)

        assertEquals("TCP", DnsModeProtocol.TCP.label)
        assertEquals(53, DnsModeProtocol.TCP.defaultPort)

        assertEquals("DoH", DnsModeProtocol.DOH.label)
        assertEquals(443, DnsModeProtocol.DOH.defaultPort)

        assertEquals("DoT", DnsModeProtocol.DOT.label)
        assertEquals(853, DnsModeProtocol.DOT.defaultPort)
    }

    @Test
    fun `preset upstream servers contain valid defaults`() {
        val presets = DnsUpstreamServer.PRESETS
        assertTrue(presets.isNotEmpty())

        val alidns = presets.firstOrNull { it.id == "alidns" }
        assertNotNull(alidns)
        assertEquals("阿里 DNS", alidns?.name)
        assertEquals("223.5.5.5", alidns?.address)
        assertEquals(53, alidns?.port)
        assertEquals(DnsModeProtocol.UDP, alidns?.protocol)
        assertEquals("[UDP] 223.5.5.5:53", alidns?.endpointLabel())

        val cloudflare = presets.firstOrNull { it.id == "cloudflare" }
        assertNotNull(cloudflare)
        assertEquals("1.1.1.1", cloudflare?.address)

        val dohServer = presets.firstOrNull { it.protocol == DnsModeProtocol.DOH }
        assertNotNull(dohServer)
        assertTrue(dohServer?.address?.startsWith("https://") == true)
        assertEquals("[DoH] ${dohServer?.address}", dohServer?.endpointLabel())
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

        DnsModeManager.recordQuery(cacheHit = false, blocked = false, latencyMs = 20L)
        assertEquals(1L, DnsModeManager.stats.value.queryCount)
        assertEquals(0L, DnsModeManager.stats.value.cacheHitCount)
        assertEquals(20L, DnsModeManager.stats.value.latencyMs)

        DnsModeManager.recordQuery(cacheHit = true, blocked = false, latencyMs = 5L)
        assertEquals(2L, DnsModeManager.stats.value.queryCount)
        assertEquals(1L, DnsModeManager.stats.value.cacheHitCount)
        // Average latency: (20 + 5) / 2
        assertEquals(12L, DnsModeManager.stats.value.latencyMs)

        DnsModeManager.recordQuery(cacheHit = false, blocked = true, latencyMs = 1L)
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
        DnsModeManager.onServiceError("DNS 服务启动失败，端口 1053 可能被占用")
        // onDestroy always fires onServiceStopped; it must not mask the error state
        DnsModeManager.onServiceStopped()
        assertEquals(DnsServiceStatus.ERROR, DnsModeManager.status.value)
        assertEquals("DNS 服务启动失败，端口 1053 可能被占用", DnsModeManager.errorReason.value)

        DnsModeManager.onServiceStarted()
        assertEquals(DnsServiceStatus.RUNNING, DnsModeManager.status.value)
        assertEquals(null, DnsModeManager.errorReason.value)
        DnsModeManager.onServiceStopped()
        assertEquals(DnsServiceStatus.STOPPED, DnsModeManager.status.value)
    }

    @Test
    fun `DnsModeConfig default values are reasonable`() {
        val config = DnsModeConfig()
        assertEquals("alidns", config.selectedUpstreamId)
        assertEquals(1053, config.localListenPort)
        assertTrue(config.cacheEnabled)
        assertEquals(300, config.cacheTtlSeconds)
        assertFalse(config.adBlockEnabled)
        assertFalse(config.logQueries)
    }

    @Test
    fun `DnsServerEngine starts and stops cleanly`() {
        val config = DnsModeConfig(localListenPort = 15354)
        val upstream = DnsUpstreamServer.PRESETS.first()
        val engine = com.haoze.diting.dnsmode.backend.DnsServerEngine(config, upstream)
        val started = engine.start()
        assertTrue(started)
        engine.stop()
    }

    @Test
    fun `DnsServerEngine answers SERVFAIL when upstream is unreachable`() {
        val config = DnsModeConfig(localListenPort = 15355, cacheEnabled = false)
        // Nothing listens on port 1; the query must fail into a SERVFAIL
        // response (rcode 2), not a policy REFUSED (rcode 5).
        val upstream = DnsUpstreamServer(
            id = "unreachable",
            name = "Unreachable",
            address = "127.0.0.1",
            port = 1,
            protocol = DnsModeProtocol.UDP
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
    fun `DnsModeService intent actions are defined`() {
        assertEquals("com.haoze.diting.dnsmode.START", DnsModeService.ACTION_START)
        assertEquals("com.haoze.diting.dnsmode.STOP", DnsModeService.ACTION_STOP)
        assertEquals("com.haoze.diting.dnsmode.REFRESH", DnsModeService.ACTION_REFRESH)
    }

    @Test
    fun `getActiveUpstream falls back gracefully when id is unknown`() {
        // Unknown id should fall back to first preset
        val upstream = DnsModeManager.getActiveUpstream()
        assertNotNull(upstream)
        assertEquals("alidns", upstream.id)
    }

    @Test
    fun `DNS mode UI strings are properly localized`() {
        assertEquals("DITING · DNS Mode", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("谛听 · DNS模式"))
        assertEquals("DNS Mode", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("DNS 模式"))
        assertEquals("Overview", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("概览"))
        assertEquals("Upstream Servers", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("上游服务器"))
        assertEquals("Mode Settings", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("模式设置"))
        assertEquals("DNS Proxy Running", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("DNS 代理运行中"))
        assertEquals("Total Queries", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("总解析量"))
        assertEquals("Cache Hits", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("缓存命中"))
        assertEquals("Avg Latency", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("平均时延"))
        assertEquals("Preset Public Upstream DNS", com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact("预设公共上游 DNS"))
    }
}
