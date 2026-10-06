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
}
