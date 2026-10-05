package com.haoze.diting.express

import com.haoze.diting.express.ui.ExpressEnvironmentChecker
import com.haoze.diting.ui.mode.AppWorkMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressModeLauncherTest {

    @Test
    fun `Express mode metadata conforms to specification`() {
        val mode = AppWorkMode.EXPRESS
        assertEquals("express", mode.storageValue)
        assertEquals("极速模式", mode.title)
        assertEquals("极速", mode.badgeText)
        assertEquals(24, mode.minApiLevel)
        assertTrue(mode.summary.contains("Kotlin 原生轻量实现"))
        assertTrue(mode.summary.contains("Android 7+"))
        assertNotNull(mode.icon)
    }

    @Test
    fun `AppWorkMode fallback and parsing works for all modes`() {
        assertEquals(AppWorkMode.EXPRESS, AppWorkMode.fromStorageValue("express"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue("normal"))
        assertEquals(AppWorkMode.DNS, AppWorkMode.fromStorageValue("dns"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue("invalid"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue(null))
    }

    @Test
    fun `ExpressVpnIntents constants are distinct and non-empty`() {
        assertEquals("com.haoze.diting.express.START_VPN", ExpressVpnIntents.ACTION_START)
        assertEquals("com.haoze.diting.express.STOP_VPN", ExpressVpnIntents.ACTION_STOP)
        assertEquals("com.haoze.diting.express.REFRESH_CONFIG", ExpressVpnIntents.ACTION_REFRESH_CONFIG)
        assertEquals("com.haoze.diting.express.SYNC_RULES", ExpressVpnIntents.ACTION_SYNC_RULES)
        assertEquals("com.haoze.diting.express.CLEAR_CACHE", ExpressVpnIntents.ACTION_CLEAR_CACHE)
        assertEquals("com.haoze.diting.express.STATUS_CHANGED", ExpressVpnIntents.ACTION_STATUS_CHANGED)
    }

    @Test
    fun `ExpressEnvironmentChecker does not throw exception`() {
        // Under JVM unit testing, Build.VERSION.SDK_INT is 0
        // This validates no linkage / classloader issues occur when invoking the checker
        val supported = ExpressEnvironmentChecker.isSupported()
        // SDK_INT is 0 in standard JVM, so minApiLevel 24 will evaluate to false
        assertEquals(false, supported)
    }
}
