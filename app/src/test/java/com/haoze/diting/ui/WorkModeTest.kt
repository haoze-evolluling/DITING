package com.haoze.diting.ui

import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
import com.haoze.diting.ui.mode.AppWorkMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkModeTest {

    @Test
    fun `AppWorkMode fromStorageValue resolves correctly`() {
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue("normal"))
        assertEquals(AppWorkMode.DNS, AppWorkMode.fromStorageValue("dns"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue("unknown"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue(null))
    }

    @Test
    fun `AppWorkMode availability states are correct`() {
        assertTrue(AppWorkMode.NORMAL.isAvailable)
        assertFalse(AppWorkMode.DNS.isAvailable)
        assertEquals("普通模式", AppWorkMode.NORMAL.title)
        assertEquals("DNS模式", AppWorkMode.DNS.title)
    }

    @Test
    fun `work mode strings are localized in English dictionary`() {
        assertEquals("Normal Mode", translateSettingsAndAppearanceExact("普通模式"))
        assertEquals("DNS Mode", translateSettingsAndAppearanceExact("DNS模式"))
        assertEquals("Mode Switch", translateSettingsAndAppearanceExact("模式切换"))
        assertEquals("Operating Mode", translateSettingsAndAppearanceExact("运行模式"))
        assertEquals("Select Operating Mode", translateSettingsAndAppearanceExact("选择工作模式"))
        assertEquals("Under Construction", translateSettingsAndAppearanceExact("施工中"))
        assertEquals("Recommended", translateSettingsAndAppearanceExact("推荐"))
        assertEquals("Switch to Normal Mode", translateSettingsAndAppearanceExact("切换回普通模式"))
        assertEquals("Re-select Mode", translateSettingsAndAppearanceExact("重新选择模式"))
        assertEquals("DNS Mode Under Construction", translateSettingsAndAppearanceExact("DNS 模式正在施工中"))
    }
}
