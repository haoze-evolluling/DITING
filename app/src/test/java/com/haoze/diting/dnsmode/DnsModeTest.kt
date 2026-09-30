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

        val cloudflare = presets.firstOrNull { it.id == "cloudflare" }
        assertNotNull(cloudflare)
        assertEquals("1.1.1.1", cloudflare?.address)

        val dohServer = presets.firstOrNull { it.protocol == DnsModeProtocol.DOH }
        assertNotNull(dohServer)
        assertTrue(dohServer?.address?.startsWith("https://") == true)
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
        assertEquals(5L, DnsModeManager.stats.value.latencyMs)

        DnsModeManager.recordQuery(cacheHit = false, blocked = true, latencyMs = 1L)
        assertEquals(3L, DnsModeManager.stats.value.queryCount)
        assertEquals(1L, DnsModeManager.stats.value.cacheHitCount)
        assertEquals(1L, DnsModeManager.stats.value.blockedCount)

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

        DnsModeManager.onServiceError()
        assertEquals(DnsServiceStatus.ERROR, DnsModeManager.status.value)
    }

    @Test
    fun `DnsModeConfig default values are reasonable`() {
        val config = DnsModeConfig()
        assertEquals("alidns", config.selectedUpstreamId)
        assertEquals(5353, config.localListenPort)
        assertTrue(config.cacheEnabled)
        assertEquals(300, config.cacheTtlSeconds)
        assertFalse(config.adBlockEnabled)
        assertTrue(config.logQueries)
    }

    @Test
    fun `DnsModeService intent actions are defined`() {
        assertEquals("com.haoze.diting.dnsmode.START", DnsModeService.ACTION_START)
        assertEquals("com.haoze.diting.dnsmode.STOP", DnsModeService.ACTION_STOP)
    }
}
