package com.haoze.diting.permission

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.BatterySaver
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.ui.graphics.vector.ImageVector
import com.haoze.diting.notification.NotificationPermissionHelper
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * 权限分级：定义在特定工作模式下的必要性等级。
 */
enum class PermissionLevel(val label: String) {
    REQUIRED("必要"),
    RECOMMENDED("推荐"),
    OPTIONAL("可选")
}

/**
 * 软件涉及的系统权限与运行能力枚举。
 */
enum class AppPermission(
    val title: String,
    val summary: String,
    val icon: ImageVector
) {
    VPN(
        title = "VPN 连接权限",
        summary = "建立本地虚拟网卡通道，用于在设备本地捕获并优化 DNS 请求，无远程数据上传",
        icon = Icons.Outlined.VpnKey
    ),
    NOTIFICATION(
        title = "通知权限",
        summary = "用于展示服务运行状态、实时速率与快捷控制，保证前台服务稳定存活",
        icon = Icons.Outlined.Notifications
    ),
    BATTERY_OPTIMIZATION(
        title = "忽略电池优化",
        summary = "防止系统在锁屏或息屏后激进杀除后台解析守护进程，保障网络稳定通畅",
        icon = Icons.Outlined.BatterySaver
    ),
    PACKAGE_QUERY(
        title = "应用列表访问",
        summary = "用于选择需要排除、禁止联网或进行 HTTPS 检查的应用，仅在本地读取",
        icon = Icons.Outlined.Layers
    ),
    SYSTEM_ALERT_WINDOW(
        title = "悬浮窗权限",
        summary = "用于在其他应用上层显示实时 DNS 解析流或网速监控悬浮球",
        icon = Icons.AutoMirrored.Outlined.OpenInNew
    );

    /**
     * 检查当前权限在当前设备上是否已经获得授予。
     */
    fun isGranted(context: Context): Boolean {
        return when (this) {
            VPN -> VpnService.prepare(context) == null
            NOTIFICATION -> NotificationPermissionHelper.hasPermission(context)
            BATTERY_OPTIMIZATION -> isBatteryOptimizationIgnored(context)
            PACKAGE_QUERY -> AppListPermissionHelper.isGranted(context)
            SYSTEM_ALERT_WINDOW -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }
        }
    }

    /**
     * 获取针对该权限的等级判定（根据所处的工作模式）。
     *
     * 服务器模式（DNS）完全不需要 VPN 权限。
     * 普通模式与极速模式必须具备 VPN 与通知权限。
     */
    fun getLevel(mode: AppWorkMode): PermissionLevel {
        return when (this) {
            VPN -> if (mode == AppWorkMode.DNS) PermissionLevel.OPTIONAL else PermissionLevel.REQUIRED
            NOTIFICATION -> PermissionLevel.REQUIRED
            BATTERY_OPTIMIZATION -> PermissionLevel.RECOMMENDED
            PACKAGE_QUERY -> if (mode == AppWorkMode.NORMAL) PermissionLevel.RECOMMENDED else PermissionLevel.OPTIONAL
            SYSTEM_ALERT_WINDOW -> PermissionLevel.OPTIONAL
        }
    }

    /**
     * 判断该权限是否适用于指定工作模式（若完全无关则返回 false）。
     */
    fun isApplicableTo(mode: AppWorkMode): Boolean {
        return when (this) {
            VPN -> mode != AppWorkMode.DNS // 服务器模式明确不适用 VPN
            NOTIFICATION -> true
            BATTERY_OPTIMIZATION -> true
            PACKAGE_QUERY -> mode == AppWorkMode.NORMAL
            SYSTEM_ALERT_WINDOW -> mode != AppWorkMode.DNS
        }
    }

    /**
     * 创建跳转或申请 Intent（如果适用）。
     */
    fun createRequestIntent(context: Context): Intent? {
        return when (this) {
            VPN -> VpnService.prepare(context)
            NOTIFICATION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    }
                } else null
            }
            BATTERY_OPTIMIZATION -> {
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                }
            }
            SYSTEM_ALERT_WINDOW -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                } else null
            }
            PACKAGE_QUERY -> {
                AppListPermissionHelper.createSettingsIntent(context)
            }
        }
    }

    companion object {
        fun isBatteryOptimizationIgnored(context: Context): Boolean {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            return powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
        }

        fun isAppListAccessible(context: Context): Boolean {
            return AppListPermissionHelper.isGranted(context)
        }
    }
}
