package com.haoze.diting.permission

import com.haoze.diting.ui.localization.translateCommonExact
import com.haoze.diting.ui.mode.AppWorkMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppListPermissionTest {

    @Test
    fun testAppListPermissionConstants() {
        assertEquals(
            "com.android.permission.GET_INSTALLED_APPS",
            AppListPermissionHelper.PERMISSION_GET_INSTALLED_APPS
        )
    }

    @Test
    fun testAppPermissionPackageQueryAttributes() {
        val perm = AppPermission.PACKAGE_QUERY
        assertEquals("应用列表访问", perm.title)
        assertNotNull(perm.summary)

        // 等级判定
        assertEquals(PermissionLevel.RECOMMENDED, perm.getLevel(AppWorkMode.NORMAL))
        assertEquals(PermissionLevel.OPTIONAL, perm.getLevel(AppWorkMode.EXPRESS))
        assertEquals(PermissionLevel.OPTIONAL, perm.getLevel(AppWorkMode.DNS))

        // 适用性判定：仅普通模式适用应用级分流、排除与检查
        assertTrue(perm.isApplicableTo(AppWorkMode.NORMAL))
        assertFalse(perm.isApplicableTo(AppWorkMode.EXPRESS))
        assertFalse(perm.isApplicableTo(AppWorkMode.DNS))
    }

    @Test
    fun testModeReadinessStateWithAppPermission() {
        // 当普通模式缺少应用列表权限时，属于推荐级别而非阻断级别
        val state = ModeReadinessState(
            mode = AppWorkMode.NORMAL,
            missingRequired = emptyList(),
            missingRecommended = listOf(AppPermission.PACKAGE_QUERY)
        )
        assertFalse("只有推荐权限缺失时不构成阻断", state.hasBlocker)
        assertFalse("存在推荐权限缺失时未完全就绪", state.isFullyReady)
        assertTrue(state.missingRecommended.contains(AppPermission.PACKAGE_QUERY))
    }

    @Test
    fun testAppListPermissionLocalization() {
        assertEquals(
            "Installed apps permission not granted",
            translateCommonExact("应用列表访问未授予")
        )
        assertEquals(
            "This permission is not granted. Used locally to select apps to exclude, block, or inspect.",
            translateCommonExact("没有授予这个权限。用于选择需要排除、禁止联网或进行 HTTPS 检查的应用，仅在本地读取。")
        )
        assertEquals(
            "Please grant Installed Apps permission in app settings",
            translateCommonExact("请在权限管理中允许“读取已安装应用列表”")
        )
        assertEquals(
            "Allow access",
            translateCommonExact("允许访问")
        )
    }

    @Test
    fun testAppManagementLocalizationForAppList() {
        val dialogMessage = "为了让你选择需要排除或进行 HTTP(S) 检查的应用，谛听需要读取设备上的应用列表。不会读取应用数据，也不会上传应用列表。"
        assertEquals(
            "DITING needs access to the installed app list so you can choose apps to exclude or inspect for HTTP(S) traffic. It does not read app data or upload the app list.",
            com.haoze.diting.ui.localization.translateAppManagementExact(dialogMessage)
        )

        val unavailableNotice = "需要应用列表访问权限才能选择应用。未授权不会影响其他功能。"
        assertEquals(
            "App-list access is required to choose apps. Denying it does not affect other features.",
            com.haoze.diting.ui.localization.translateAppManagementExact(unavailableNotice)
        )
    }

    @Test
    fun testAppListPermissionCacheInvalidation() {
        // 验证清空缓存方法正常执行且不抛异常
        AppListPermissionHelper.invalidateCache()
    }
}
