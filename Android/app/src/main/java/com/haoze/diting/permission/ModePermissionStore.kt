package com.haoze.diting.permission

import android.content.Context
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * 持久化存储各模式的新手引导完成状态、权限披露记录与建议项忽略标记。
 */
object ModePermissionStore {
    private const val PREFS_NAME = "mode_permission_preferences"
    private const val KEY_PREFIX_ONBOARDING_COMPLETED = "onboarding_completed_"
    private const val KEY_PREFIX_PERMISSION_EXPLAINED = "permission_explained_"
    private const val KEY_PREFIX_RECOMMENDATION_DISMISSED = "recommendation_dismissed_"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * 判断指定模式是否已经完成过专属新手引导。
     */
    fun isOnboardingCompleted(context: Context, mode: AppWorkMode): Boolean {
        return prefs(context).getBoolean(KEY_PREFIX_ONBOARDING_COMPLETED + mode.storageValue, false)
    }

    /**
     * 标记指定模式的新手引导完成状态。
     */
    fun setOnboardingCompleted(context: Context, mode: AppWorkMode, completed: Boolean = true) {
        prefs(context).edit()
            .putBoolean(KEY_PREFIX_ONBOARDING_COMPLETED + mode.storageValue, completed)
            .apply()
    }

    /**
     * 重置指定模式的新手引导状态，允许重新唤起向导。
     */
    fun resetOnboarding(context: Context, mode: AppWorkMode) {
        prefs(context).edit()
            .remove(KEY_PREFIX_ONBOARDING_COMPLETED + mode.storageValue)
            .apply()
    }

    /**
     * 判断用户是否已选择暂时忽略某项建议级权限（如电池优化）。
     */
    fun isRecommendationDismissed(context: Context, permission: AppPermission): Boolean {
        return prefs(context).getBoolean(KEY_PREFIX_RECOMMENDATION_DISMISSED + permission.name, false)
    }

    /**
     * 记录用户忽略建议项的决定。
     */
    fun setRecommendationDismissed(context: Context, permission: AppPermission, dismissed: Boolean = true) {
        prefs(context).edit()
            .putBoolean(KEY_PREFIX_RECOMMENDATION_DISMISSED + permission.name, dismissed)
            .apply()
    }

    /**
     * 判断某项权限的前置说明弹窗是否已向用户展示过。
     */
    fun isPermissionExplained(context: Context, permission: AppPermission): Boolean {
        return prefs(context).getBoolean(KEY_PREFIX_PERMISSION_EXPLAINED + permission.name, false)
    }

    /**
     * 记录某项权限的前置说明展示状态。
     */
    fun setPermissionExplained(context: Context, permission: AppPermission, explained: Boolean = true) {
        prefs(context).edit()
            .putBoolean(KEY_PREFIX_PERMISSION_EXPLAINED + permission.name, explained)
            .apply()
    }

    /**
     * 清除所有被忽略的推荐项，恢复提醒。
     */
    fun clearDismissedRecommendations(context: Context) {
        val editor = prefs(context).edit()
        AppPermission.entries.forEach { perm ->
            editor.remove(KEY_PREFIX_RECOMMENDATION_DISMISSED + perm.name)
        }
        editor.apply()
    }
}
