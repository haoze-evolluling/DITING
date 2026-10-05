package com.haoze.diting.permission

import android.content.Context
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * 描述指定工作模式下的运行环境与权限就绪评估结果。
 */
data class ModeReadinessState(
    val mode: AppWorkMode,
    val missingRequired: List<AppPermission>,
    val missingRecommended: List<AppPermission>
) {
    /** 是否存在阻断级权限缺失（无法正常启动核心服务） */
    val hasBlocker: Boolean get() = missingRequired.isNotEmpty()

    /** 是否完全就绪（核心与保活推荐均已授权） */
    val isFullyReady: Boolean get() = missingRequired.isEmpty() && missingRecommended.isEmpty()

    /** 过滤出用户尚未显式忽略的建议项 */
    fun getActiveRecommended(context: Context): List<AppPermission> {
        return missingRecommended.filter { !ModePermissionStore.isRecommendationDismissed(context, it) }
    }
}

/**
 * 就绪状态评估器。
 */
object ModeReadinessEvaluator {

    fun evaluate(context: Context, mode: AppWorkMode): ModeReadinessState {
        val missingReq = mutableListOf<AppPermission>()
        val missingRec = mutableListOf<AppPermission>()

        // 核心权限检查：VPN (仅普通与极速模式)
        if (mode != AppWorkMode.DNS) {
            if (!AppPermission.VPN.isGranted(context)) {
                missingReq.add(AppPermission.VPN)
            }
        }

        // 核心权限检查：通知 (所有模式前台服务)
        if (!AppPermission.NOTIFICATION.isGranted(context)) {
            missingReq.add(AppPermission.NOTIFICATION)
        }

        // 保活推荐检查：电池优化 (所有模式)
        if (!AppPermission.BATTERY_OPTIMIZATION.isGranted(context)) {
            missingRec.add(AppPermission.BATTERY_OPTIMIZATION)
        }

        return ModeReadinessState(
            mode = mode,
            missingRequired = missingReq,
            missingRecommended = missingRec
        )
    }
}
