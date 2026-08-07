package com.haoze.dnssr.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class MainScreenTextTest {

    @Test
    fun raceProviderSummaryHandlesEmptyAndShortLists() {
        assertEquals("未选择服务商", raceProviderSummary(emptyList()))
        assertEquals("已选 1 个：服务商 A", raceProviderSummary(listOf("服务商 A")))
        assertEquals("已选 2 个：服务商 A、服务商 B", raceProviderSummary(listOf("服务商 A", "服务商 B")))
    }

    @Test
    fun raceProviderSummaryLimitsDisplayedNames() {
        val names = listOf("服务商 A", "服务商 B", "服务商 C", "服务商 D")

        assertEquals("已选 4 个：服务商 A、服务商 B 等", raceProviderSummary(names))
    }
}
