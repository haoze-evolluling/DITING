package com.haoze.diting.ui

import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
import com.haoze.diting.ui.mode.AppWorkMode
import org.junit.Assert.assertEquals
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
        assertTrue(AppWorkMode.DNS.isAvailable)
        assertEquals("普通模式", AppWorkMode.NORMAL.title)
        assertEquals("DNS 模式", AppWorkMode.DNS.title)
        assertEquals("推荐", AppWorkMode.NORMAL.badgeText)
        assertEquals("轻量", AppWorkMode.DNS.badgeText)
    }

    @Test
    fun `work mode strings are localized in English dictionary`() {
        assertEquals("Normal Mode", translateSettingsAndAppearanceExact("普通模式"))
        assertEquals("DNS Mode", translateSettingsAndAppearanceExact("DNS 模式"))
        assertEquals("Mode Switch", translateSettingsAndAppearanceExact("模式切换"))
        assertEquals("Operating Mode", translateSettingsAndAppearanceExact("运行模式"))
        assertEquals("Select Operating Mode", translateSettingsAndAppearanceExact("选择工作模式"))
        assertEquals("Recommended", translateSettingsAndAppearanceExact("推荐"))
        assertEquals("Lightweight", translateSettingsAndAppearanceExact("轻量"))
        assertEquals("Switch to Normal Mode", translateSettingsAndAppearanceExact("切换为普通模式"))
        assertEquals("Re-select Work Mode", translateSettingsAndAppearanceExact("重新选择工作模式"))
        assertEquals("Current Running Mode", translateSettingsAndAppearanceExact("当前运行模式"))
        assertEquals("Currently Active", translateSettingsAndAppearanceExact("当前生效中"))
        assertEquals("Active", translateSettingsAndAppearanceExact("运行中"))
        assertEquals("Mode Capability Comparison", translateSettingsAndAppearanceExact("模式特性对比"))
        assertEquals("Confirm Mode Switch", translateSettingsAndAppearanceExact("确认切换运行模式"))
        assertEquals("Already in this mode", translateSettingsAndAppearanceExact("当前已处于该模式"))
        assertEquals("Get Started with this Mode", translateSettingsAndAppearanceExact("以此模式开启体验"))
    }
}
