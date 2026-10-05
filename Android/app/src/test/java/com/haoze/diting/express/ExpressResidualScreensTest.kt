package com.haoze.diting.express

import com.haoze.diting.express.ui.ExpressBottomBarDestination
import com.haoze.diting.ui.AboutCapability
import com.haoze.diting.ui.BottomBarDestination
import com.haoze.diting.ui.aboutBoundaries
import com.haoze.diting.ui.aboutCapabilities
import com.haoze.diting.ui.getAboutBoundaries
import com.haoze.diting.ui.getAboutCapabilities
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests verifying that Express Mode screens physically omit unadapted/residual
 * full-tunnel components, entries, and capabilities.
 */
class ExpressResidualScreensTest {

    @Test
    fun testExpressBottomBarDestinationsAreConstrained() {
        val allDestinations = ExpressBottomBarDestination.entries
        assertEquals(4, allDestinations.size)

        val destinationIds = allDestinations.map { it.id }.toSet()
        assertTrue(destinationIds.contains("home"))
        assertTrue(destinationIds.contains("feature_hub"))
        assertTrue(destinationIds.contains("log_dashboard"))
        assertTrue(destinationIds.contains("settings"))

        // Full tunnel items must not exist in ExpressBottomBarDestination
        assertFalse(destinationIds.contains("app_traffic_stats"))
        assertFalse(destinationIds.contains("network_tools"))
    }

    @Test
    fun testExpressBottomBarFromLegacyFiltersResidualItems() {
        assertEquals(ExpressBottomBarDestination.HOME, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.HOME))
        assertEquals(ExpressBottomBarDestination.FEATURE_HUB, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.FEATURE_HUB))
        assertEquals(ExpressBottomBarDestination.LOG_DASHBOARD, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.LOG_DASHBOARD))
        assertEquals(ExpressBottomBarDestination.SETTINGS, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.SETTINGS))

        // Residual destinations from normal mode must be filtered out to null
        assertNull(ExpressBottomBarDestination.fromLegacy(BottomBarDestination.APP_TRAFFIC_STATS))
        assertNull(ExpressBottomBarDestination.fromLegacy(BottomBarDestination.NETWORK_TOOLS))
    }

    @Test
    fun testAboutCapabilitiesForExpressModeOmitFullTunnelFeatures() {
        val normalCapabilities = getAboutCapabilities(isExpress = false)
        val expressCapabilities = getAboutCapabilities(isExpress = true)

        assertEquals(8, normalCapabilities.size)
        assertEquals(6, expressCapabilities.size)

        val expressTitles = expressCapabilities.map { it.title }.toSet()
        val expressDescriptions = expressCapabilities.map { it.description }.joinToString(" ")

        // Express capabilities must not include application control or HTTPS inspection
        assertFalse(expressTitles.contains("应用管控"))
        assertFalse(expressTitles.contains("HTTPS 流量检查"))
        assertFalse(expressDescriptions.contains("根证书"))
        assertFalse(expressDescriptions.contains("阻止联网"))

        // Express capabilities must include DNS-focused items
        assertTrue(expressTitles.contains("加密上游"))
        assertTrue(expressTitles.contains("规则与缓存"))
        assertTrue(expressTitles.contains("可观测性"))
        assertTrue(expressTitles.contains("独立引导"))
        assertTrue(expressTitles.contains("配置流转"))
        assertTrue(expressTitles.contains("快捷控制"))
    }

    @Test
    fun testAboutBoundariesForExpressModeClarifyDnsScope() {
        val expressBoundaries = getAboutBoundaries(isExpress = true)
        val normalBoundaries = getAboutBoundaries(isExpress = false)

        val expressTitles = expressBoundaries.map { it.first }
        val expressDescriptions = expressBoundaries.map { it.second }.joinToString(" ")

        assertTrue(expressTitles.contains("极速原生 DNS 窄路由"))
        assertTrue(expressDescriptions.contains("纯 Kotlin 原生轻量窄路由接管 UDP/TCP 53 端口 DNS 请求"))
        assertTrue(expressDescriptions.contains("设备常规应用数据直连物理网络，不经过 VPN 协议栈"))

        val normalDescriptions = normalBoundaries.map { it.second }.joinToString(" ")
        assertTrue(normalDescriptions.contains("Go 用户态网络栈接管 TCP、UDP、DNS 和 HTTP(S) 流量"))
        assertFalse(expressDescriptions.contains("Go 用户态网络栈"))
    }
}
