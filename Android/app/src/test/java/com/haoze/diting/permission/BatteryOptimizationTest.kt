package com.haoze.diting.permission

import android.provider.Settings
import com.haoze.diting.ui.localization.translateCommonExact
import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
import com.haoze.diting.ui.mode.AppWorkMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryOptimizationTest {

    @Test
    fun testAppPermissionBatteryOptimizationAttributes() {
        val perm = AppPermission.BATTERY_OPTIMIZATION
        assertEquals("忽略电池优化", perm.title)
        assertNotNull(perm.summary)

        // 验证三种模式下的权限等级皆为推荐项（非阻断核心）
        assertEquals(PermissionLevel.RECOMMENDED, perm.getLevel(AppWorkMode.NORMAL))
        assertEquals(PermissionLevel.RECOMMENDED, perm.getLevel(AppWorkMode.EXPRESS))
        assertEquals(PermissionLevel.RECOMMENDED, perm.getLevel(AppWorkMode.DNS))

        // 验证三种模式下皆适用保活推荐
        assertTrue(perm.isApplicableTo(AppWorkMode.NORMAL))
        assertTrue(perm.isApplicableTo(AppWorkMode.EXPRESS))
        assertTrue(perm.isApplicableTo(AppWorkMode.DNS))
    }

    @Test
    fun testModeReadinessStateWithBatteryOptimization() {
        // 当极速模式仅缺少电池优化权限时，属于推荐级别而非阻断启动
        val expressState = ModeReadinessState(
            mode = AppWorkMode.EXPRESS,
            missingRequired = emptyList(),
            missingRecommended = listOf(AppPermission.BATTERY_OPTIMIZATION)
        )
        assertFalse("仅缺少电池优化不构成阻断", expressState.hasBlocker)
        assertFalse("缺少建议项时未完全就绪", expressState.isFullyReady)
        assertTrue(expressState.missingRecommended.contains(AppPermission.BATTERY_OPTIMIZATION))

        // 当普通模式同时具备核心与建议权限时完全就绪
        val fullyReadyState = ModeReadinessState(
            mode = AppWorkMode.NORMAL,
            missingRequired = emptyList(),
            missingRecommended = emptyList()
        )
        assertFalse(fullyReadyState.hasBlocker)
        assertTrue(fullyReadyState.isFullyReady)
    }

    @Test
    fun testBatteryOptimizationHelperCacheInvalidation() {
        // 验证重置缓存接口正常执行且不产生异常
        BatteryOptimizationHelper.invalidateCache()
    }

    @Test
    fun testBatteryOptimizationActionConstants() {
        assertEquals(
            "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS",
            Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
        )
        assertEquals(
            "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
        )
    }

    @Test
    fun testBatteryOptimizationLocalization() {
        assertEquals(
            "Battery optimization not granted",
            translateCommonExact("忽略电池优化未授予")
        )
        assertEquals(
            "This permission is not granted. It is recommended to add DITING to the battery optimization whitelist to prevent background daemon termination.",
            translateCommonExact("没有授予这个权限。建议将谛听加入电池优化白名单，防止后台守护进程被系统强制回收。")
        )
        assertEquals(
            "Ignored",
            translateCommonExact("已忽略")
        )
        assertEquals(
            "Don't show again",
            translateCommonExact("不再提示")
        )
        assertEquals(
            "Ignore battery optimizations",
            translateSettingsAndAppearanceExact("忽略电池优化")
        )
        assertEquals(
            "Battery optimization ignored",
            translateSettingsAndAppearanceExact("已忽略电池优化")
        )
    }
}
