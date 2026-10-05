package com.haoze.diting.ui

import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsUsageWizardTest {

    @Test
    fun testUsageWizardDestinationConfiguredInOtherSettings() {
        val wizard = ScreenDestinations.usageWizard
        assertEquals(Routes.USAGE_WIZARD, wizard.route)
        assertEquals("使用向导", wizard.title)
        assertEquals(SettingsSection.OTHER, wizard.mainSection)

        val otherEntries = ScreenDestinations.mainEntries.filter { it.mainSection == SettingsSection.OTHER }
        assertTrue("mainEntries 中 OTHER 分应包含使用向导", otherEntries.any { it.route == Routes.USAGE_WIZARD })
    }

    @Test
    fun testUsageWizardLocalization() {
        assertEquals("Usage Wizard", translateSettingsAndAppearanceExact("使用向导"))
        assertNotNull(translateSettingsAndAppearanceExact("查看当前工作模式的架构原理、权限配置与上手指引"))
        assertNotNull(translateSettingsAndAppearanceExact("查看服务器模式架构原理、局域网配置与就绪指引"))
    }
}
