package com.haoze.diting.dnsmode

import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.backend.DnsModePreferences
import com.haoze.diting.dnsmode.backend.DnsModeService
import com.haoze.diting.dnsmode.model.DnsListenPortValidator
import com.haoze.diting.dnsmode.model.DnsModeConfig
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.dnsmode.model.DnsUpstreamValidator
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.ui.localization.translateRulesAndSubscriptionExact
import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
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
    fun `DnsUpstreamServer presets contain udp doh and dot endpoints`() {
        val presets = DnsUpstreamServer.PRESETS
        assertEquals("alidns", presets.first().id)
        assertEquals("1.1.1.1", presets.firstOrNull { it.id == "cloudflare" }?.address)

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
        assertEquals("alidns", config.selectedUpstreamId)
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

        assertNull(validator.validateAddress(DnsModeProtocol.UDP, "223.5.5.5"))
        assertNull(validator.validateAddress(DnsModeProtocol.UDP, "2001:db8::1"))
        assertNull(validator.validateAddress(DnsModeProtocol.DOT, "dns.alidns.com"))
        assertNull(validator.validateAddress(DnsModeProtocol.DOH, "https://dns.alidns.com/dns-query"))
        assertNotNull(validator.validateAddress(DnsModeProtocol.DOH, "http://dns.alidns.com/dns-query"))
        assertNotNull(validator.validateAddress(DnsModeProtocol.UDP, ""))
        assertNotNull(validator.validateAddress(DnsModeProtocol.UDP, "1 1 1 1"))

        assertNull(validator.validatePort("", DnsModeProtocol.UDP))
        assertNull(validator.validatePort("853", DnsModeProtocol.DOT))
        assertNotNull(validator.validatePort("0", DnsModeProtocol.UDP))
        assertNotNull(validator.validatePort("70000", DnsModeProtocol.UDP))
        assertNotNull(validator.validatePort("abc", DnsModeProtocol.UDP))
        assertNull(validator.validatePort("abc", DnsModeProtocol.DOH))

        assertEquals(53, validator.parsePort("", DnsModeProtocol.UDP))
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
                name = "自定义 UDP",
                address = "192.168.1.2",
                port = 5335,
                protocol = DnsModeProtocol.UDP,
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

    @Test
    fun `DNS mode UI strings are properly localized`() {
        assertEquals("DITING · DNS Mode", translateSettingsAndAppearanceExact("谛听 · DNS 模式"))
        assertEquals("DNS Mode", translateSettingsAndAppearanceExact("DNS 模式"))
        assertEquals("Upstream Servers", translateSettingsAndAppearanceExact("上游服务器"))
        assertEquals("Mode Settings", translateSettingsAndAppearanceExact("模式设置"))
        assertEquals("DNS Mode Running", translateSettingsAndAppearanceExact("DNS 模式运行中"))
        assertEquals("DNS Mode Stopped", translateSettingsAndAppearanceExact("DNS 模式已停止"))
        assertEquals("Total Queries", translateSettingsAndAppearanceExact("总查询量"))
        assertEquals("Cache Hits", translateSettingsAndAppearanceExact("缓存命中"))
        assertEquals("Blocked", translateSettingsAndAppearanceExact("已拦截"))
        assertEquals("Uptime", translateSettingsAndAppearanceExact("运行时长"))
        assertEquals("Avg Latency", translateSettingsAndAppearanceExact("平均时延"))
        assertEquals("Preset Public Upstream DNS", translateSettingsAndAppearanceExact("预设公共上游 DNS"))
        assertEquals("Switch to Normal Mode", translateSettingsAndAppearanceExact("切换为普通模式"))
        assertEquals("Re-select Work Mode", translateSettingsAndAppearanceExact("重新选择工作模式"))
        assertEquals(
            "Failed to start DNS service. The listen port may already be in use",
            translateSettingsAndAppearanceExact("DNS 服务启动失败，监听端口可能被占用")
        )
        assertEquals(
            "Failed to update DNS service. The listen port may already be in use",
            translateSettingsAndAppearanceExact("DNS 服务更新失败，监听端口可能被占用")
        )
        assertEquals(
            "DITING · DNS Mode Running",
            translateSettingsAndAppearanceExact("谛听 · DNS 模式运行中")
        )
        assertEquals("Add Custom Upstream", translateSettingsAndAppearanceExact("添加自定义上游"))
        assertEquals("Edit Custom Upstream", translateSettingsAndAppearanceExact("编辑自定义上游"))
        assertEquals("Custom Upstreams", translateSettingsAndAppearanceExact("自定义上游"))
        assertEquals("Clear all statistics of this run", translateSettingsAndAppearanceExact("清空本次运行的统计数据"))
        assertEquals(
            "Keep the DNS service running stably in the background",
            translateSettingsAndAppearanceExact("保持 DNS 服务在后台稳定运行")
        )
        assertEquals("Ali DNS", translateSettingsAndAppearanceExact("阿里 DNS"))
        assertEquals(
            "Port the DNS service listens on locally; defaults to 1053",
            translateSettingsAndAppearanceExact("DNS 服务在本机监听的端口，默认 1053")
        )
        assertEquals(
            "Range 1024-65535, default 1053",
            translateSettingsAndAppearanceExact("范围 1024-65535，默认 1053")
        )
        // DNS mode isolated rule management strings
        assertEquals("Enable domain filtering", translateRulesAndSubscriptionExact("启用域名过滤"))
        assertEquals(
            "Enable malicious domain blocking and allowlist pass-through",
            translateRulesAndSubscriptionExact("开启恶意域名拦截与白名单放行")
        )
        assertEquals("Rule Management", translateRulesAndSubscriptionExact("规则管理"))
        assertEquals("Hosts Rewrites", translateRulesAndSubscriptionExact("Hosts 覆写"))
        assertEquals(
            "URL rules are only supported in normal mode",
            translateRulesAndSubscriptionExact("URL 规则仅普通模式支持")
        )
        assertEquals(
            "Alibaba public DNS with low latency in mainland China",
            translateSettingsAndAppearanceExact("阿里巴巴公共 DNS，国内解析低时延")
        )
    }
}
