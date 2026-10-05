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
        assertEquals(AppWorkMode.EXPRESS, AppWorkMode.fromStorageValue("express"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue("unknown"))
        assertEquals(AppWorkMode.NORMAL, AppWorkMode.fromStorageValue(null))
    }

    @Test
    fun `AppWorkMode availability states are correct`() {
        assertTrue(AppWorkMode.NORMAL.isAvailable)
        assertTrue(AppWorkMode.DNS.isAvailable)
        assertTrue(AppWorkMode.EXPRESS.isAvailable)
        assertEquals("普通模式", AppWorkMode.NORMAL.title)
        assertEquals("服务器模式", AppWorkMode.DNS.title)
        assertEquals("极速模式", AppWorkMode.EXPRESS.title)
        assertEquals("推荐", AppWorkMode.NORMAL.badgeText)
        assertEquals("轻量", AppWorkMode.DNS.badgeText)
        assertEquals("极速", AppWorkMode.EXPRESS.badgeText)
        assertEquals(29, AppWorkMode.NORMAL.minApiLevel)
        assertEquals(29, AppWorkMode.DNS.minApiLevel)
        assertEquals(24, AppWorkMode.EXPRESS.minApiLevel)
        assertEquals("express", AppWorkMode.EXPRESS.storageValue)
        assertTrue(AppWorkMode.EXPRESS.summary.contains("Android 7+"))
    }
}
