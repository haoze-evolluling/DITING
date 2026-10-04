package com.haoze.diting.ui

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
}
