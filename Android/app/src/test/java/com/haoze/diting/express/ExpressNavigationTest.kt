package com.haoze.diting.express

import com.haoze.diting.express.ui.ExpressBottomBarDestination
import com.haoze.diting.ui.BottomBarDestination
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExpressNavigationTest {

    @Test
    fun `default destinations are HOME, FEATURE_HUB and LOG_DASHBOARD`() {
        val defaults = ExpressBottomBarDestination.DEFAULT_DESTINATIONS
        assertEquals(3, defaults.size)
        assertEquals(ExpressBottomBarDestination.HOME, defaults[0])
        assertEquals(ExpressBottomBarDestination.FEATURE_HUB, defaults[1])
        assertEquals(ExpressBottomBarDestination.LOG_DASHBOARD, defaults[2])
    }

    @Test
    fun `fromId resolves only supported Express destination ids`() {
        assertEquals(ExpressBottomBarDestination.HOME, ExpressBottomBarDestination.fromId("home"))
        assertEquals(ExpressBottomBarDestination.FEATURE_HUB, ExpressBottomBarDestination.fromId("feature_hub"))
        assertEquals(ExpressBottomBarDestination.LOG_DASHBOARD, ExpressBottomBarDestination.fromId("log_dashboard"))
        assertEquals(ExpressBottomBarDestination.SETTINGS, ExpressBottomBarDestination.fromId("settings"))
        assertNull(ExpressBottomBarDestination.fromId("app_traffic_stats"))
        assertNull(ExpressBottomBarDestination.fromId("network_tools"))
        assertNull(ExpressBottomBarDestination.fromId("unknown"))
    }

    @Test
    fun `fromLegacy correctly maps supported destinations and filters unsupported ones`() {
        assertEquals(ExpressBottomBarDestination.HOME, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.HOME))
        assertEquals(ExpressBottomBarDestination.FEATURE_HUB, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.FEATURE_HUB))
        assertEquals(ExpressBottomBarDestination.LOG_DASHBOARD, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.LOG_DASHBOARD))
        assertEquals(ExpressBottomBarDestination.SETTINGS, ExpressBottomBarDestination.fromLegacy(BottomBarDestination.SETTINGS))
        assertNull(ExpressBottomBarDestination.fromLegacy(BottomBarDestination.APP_TRAFFIC_STATS))
        assertNull(ExpressBottomBarDestination.fromLegacy(BottomBarDestination.NETWORK_TOOLS))
    }

    @Test
    fun `parseJsonList filters out full tunnel destinations and falls back safely`() {
        val json = """["home", "app_traffic_stats", "network_tools", "feature_hub"]"""
        val result = ExpressBottomBarDestination.parseJsonList(json)
        assertEquals(listOf(ExpressBottomBarDestination.HOME, ExpressBottomBarDestination.FEATURE_HUB), result)

        val jsonOnlyUnsupported = """["app_traffic_stats", "network_tools"]"""
        val resultFallback = ExpressBottomBarDestination.parseJsonList(jsonOnlyUnsupported)
        assertEquals(ExpressBottomBarDestination.DEFAULT_DESTINATIONS, resultFallback)
    }

    @Test
    fun `toJsonList and parseJsonList round trip preserves order`() {
        val input = listOf(
            ExpressBottomBarDestination.SETTINGS,
            ExpressBottomBarDestination.LOG_DASHBOARD,
            ExpressBottomBarDestination.HOME
        )
        val json = ExpressBottomBarDestination.toJsonList(input)
        val output = ExpressBottomBarDestination.parseJsonList(json)
        assertEquals(input, output)
    }
}
