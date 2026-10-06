package com.haoze.diting.main

import com.haoze.diting.MainActivity
import com.haoze.diting.ui.mode.AppWorkMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MainDecompositionTest {

    @Test
    fun `MainActivity constants remain consistent with public contract`() {
        assertEquals("auto_start_vpn", MainActivity.EXTRA_AUTO_START_VPN)
        assertEquals("main_work_mode_changed", MainActivity.EXTRA_WORK_MODE_CHANGED)
        assertEquals("main_target_work_mode", MainActivity.EXTRA_TARGET_WORK_MODE)
    }

    @Test
    fun `MainWorkModeCoordinator initializes with sensible defaults`() {
        val coordinator = MainWorkModeCoordinator()
        assertEquals(AppWorkMode.NORMAL, coordinator.currentWorkMode)
        assertFalse(coordinator.hasSelectedWorkMode)
        assertEquals(0L, coordinator.resetToHomeTrigger)
    }

    @Test
    fun `MainStartupCoordinator startup tuning constants adhere to spec`() {
        assertEquals(500L, MainStartupCoordinator.DATABASE_WARMUP_DELAY_MS)
    }

    @Test
    fun `MainWorkModeCoordinator constructor callbacks default to safe no-ops`() {
        var initialized = false
        var stopped = false
        var refreshed = false

        val coordinator = MainWorkModeCoordinator(
            onInitializeAcceptedExperience = { initialized = true },
            onStopVpn = { stopped = true },
            onRefreshNormalStatus = { refreshed = true }
        )

        assertEquals(AppWorkMode.NORMAL, coordinator.currentWorkMode)
        assertFalse(coordinator.hasSelectedWorkMode)
        assertFalse(initialized)
        assertFalse(stopped)
        assertFalse(refreshed)
    }
}
