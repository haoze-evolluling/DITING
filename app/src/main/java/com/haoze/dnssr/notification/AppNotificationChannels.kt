package com.haoze.dnssr.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.localizedText

/**
 * Central registry for creating and configuring every notification channel
 * the app uses.
 */
object AppNotificationChannels {

    const val CHANNEL_VPN_SERVICE = "diting_vpn_service_channel"
    const val CHANNEL_VPN_MONITOR = "diting_vpn_monitor_channel"
    const val CHANNEL_RULE_OPERATIONS = "diting_rule_operations_channel"
    const val CHANNEL_SUBSCRIPTION_AUTO_UPDATE = "diting_subscription_auto_update_channel"
    const val CHANNEL_APP_UPDATE = "diting_app_update_channel"

    /**
     * Creates or updates all notification channels.
     */
    fun createAllChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // 1. VPN foreground service notification channel
        val vpnServiceChannel = NotificationChannel(
            CHANNEL_VPN_SERVICE,
            localizedText(context, "VPN 连接服务"),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = localizedText(context, "显示 DNS VPN 运行中的连接状态与实时速率")
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }

        // 2. Persistent monitor notification channel shown while the VPN is disconnected
        val vpnMonitorChannel = NotificationChannel(
            CHANNEL_VPN_MONITOR,
            localizedText(context, "VPN 状态提醒"),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = localizedText(context, "在 VPN 未运行时提供快速连接入口")
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }

        // 3. Rule operation and import progress notification channel
        val ruleOperationsChannel = NotificationChannel(
            CHANNEL_RULE_OPERATIONS,
            context.getString(R.string.rule_update_channel),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = localizedText(context, "显示规则导入和更新进度")
            setShowBadge(false)
        }

        // 4. Subscription auto-update completion summary channel
        val subAutoUpdateChannel = NotificationChannel(
            CHANNEL_SUBSCRIPTION_AUTO_UPDATE,
            localizedText(context, "规则订阅自动更新"),
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = localizedText(context, "规则订阅自动更新完成后的结果通知")
            setShowBadge(true)
        }

        // 5. App download and update notification channel
        val appUpdateChannel = NotificationChannel(
            CHANNEL_APP_UPDATE,
            context.getString(R.string.app_update_channel),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = localizedText(context, "显示应用安装包下载进度与安装提示")
            setShowBadge(false)
        }

        manager.createNotificationChannels(
            listOf(
                vpnServiceChannel,
                vpnMonitorChannel,
                ruleOperationsChannel,
                subAutoUpdateChannel,
                appUpdateChannel
            )
        )
    }
}
