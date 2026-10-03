package com.haoze.diting.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BottomBarDestinationTest {

    @Test
    fun `default destinations are HOME, FEATURE_HUB and LOG_DASHBOARD`() {
        val defaults = BottomBarDestination.DEFAULT_DESTINATIONS
        assertEquals(3, defaults.size)
        assertEquals(BottomBarDestination.HOME, defaults[0])
        assertEquals(BottomBarDestination.FEATURE_HUB, defaults[1])
        assertEquals(BottomBarDestination.LOG_DASHBOARD, defaults[2])
    }

    @Test
    fun `fromId resolves all valid destination ids`() {
        assertEquals(BottomBarDestination.HOME, BottomBarDestination.fromId("home"))
        assertEquals(BottomBarDestination.FEATURE_HUB, BottomBarDestination.fromId("feature_hub"))
        assertEquals(BottomBarDestination.LOG_DASHBOARD, BottomBarDestination.fromId("log_dashboard"))
        assertEquals(BottomBarDestination.APP_TRAFFIC_STATS, BottomBarDestination.fromId("app_traffic_stats"))
        assertEquals(BottomBarDestination.NETWORK_TOOLS, BottomBarDestination.fromId("network_tools"))
        assertEquals(BottomBarDestination.SETTINGS, BottomBarDestination.fromId("settings"))
        assertNull(BottomBarDestination.fromId("unknown_id"))
        assertNull(BottomBarDestination.fromId(""))
    }

    @Test
    fun `parseJsonList returns defaults for null or empty`() {
        assertEquals(BottomBarDestination.DEFAULT_DESTINATIONS, BottomBarDestination.parseJsonList(null))
        assertEquals(BottomBarDestination.DEFAULT_DESTINATIONS, BottomBarDestination.parseJsonList(""))
        assertEquals(BottomBarDestination.DEFAULT_DESTINATIONS, BottomBarDestination.parseJsonList("   "))
        assertEquals(BottomBarDestination.DEFAULT_DESTINATIONS, BottomBarDestination.parseJsonList("invalid_json"))
    }

    @Test
    fun `parseJsonList filters out unknown and duplicate items`() {
        val json = """["home", "unknown", "home", "network_tools"]"""
        val result = BottomBarDestination.parseJsonList(json)
        assertEquals(listOf(BottomBarDestination.HOME, BottomBarDestination.NETWORK_TOOLS), result)
    }

    @Test
    fun `parseJsonList falls back to default if fewer than 2 items`() {
        val json = """["home"]"""
        val result = BottomBarDestination.parseJsonList(json)
        assertEquals(BottomBarDestination.DEFAULT_DESTINATIONS, result)
    }

    @Test
    fun `parseJsonList caps at max 4 items`() {
        val json = """["home", "feature_hub", "log_dashboard", "app_traffic_stats", "network_tools"]"""
        val result = BottomBarDestination.parseJsonList(json)
        assertEquals(4, result.size)
        assertEquals(
            listOf(
                BottomBarDestination.HOME,
                BottomBarDestination.FEATURE_HUB,
                BottomBarDestination.LOG_DASHBOARD,
                BottomBarDestination.APP_TRAFFIC_STATS
            ),
            result
        )
    }

    @Test
    fun `toJsonList and parseJsonList round trip preserves order`() {
        val input = listOf(
            BottomBarDestination.NETWORK_TOOLS,
            BottomBarDestination.LOG_DASHBOARD,
            BottomBarDestination.HOME
        )
        val json = BottomBarDestination.toJsonList(input)
        val output = BottomBarDestination.parseJsonList(json)
        assertEquals(input, output)
    }

    @Test
    fun `toJsonList falls back to default when input has less than 2 items`() {
        val input = listOf(BottomBarDestination.SETTINGS)
        val json = BottomBarDestination.toJsonList(input)
        val output = BottomBarDestination.parseJsonList(json)
        assertEquals(BottomBarDestination.DEFAULT_DESTINATIONS, output)
    }
}
