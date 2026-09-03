package com.haoze.dnssr.notification

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.localizedText

/**
 * 统一管理应用所有通知渠道的注册与配置。
 */
object AppNotificationChannels {

    const val CHANNEL_VPN_SERVICE = "diting_vpn_service_channel"
    const val CHANNEL_VPN_MONITOR = "diting_vpn_monitor_channel"
    const val CHANNEL_RULE_OPERATIONS = "diting_rule_operations_channel"
    const val CHANNEL_SUBSCRIPTION_AUTO_UPDATE = "diting_subscription_auto_update_channel"
    const val CHANNEL_APP_UPDATE = "diting_app_update_channel"

    /**
     * 注册/更新所有通知渠道。
     */
    fun createAllChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // 1. VPN 前台运行服务通知渠道
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

        // 2. VPN 未连接常驻监控通知渠道
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

        // 3. 规则操作与导入进度通知渠道
        val ruleOperationsChannel = NotificationChannel(
            CHANNEL_RULE_OPERATIONS,
            context.getString(R.string.rule_update_channel),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = localizedText(context, "显示规则导入和更新进度")
            setShowBadge(false)
        }

        // 4. 订阅自动更新完成摘要通知渠道
        val subAutoUpdateChannel = NotificationChannel(
            CHANNEL_SUBSCRIPTION_AUTO_UPDATE,
            localizedText(context, "规则订阅自动更新"),
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = localizedText(context, "规则订阅自动更新完成后的结果通知")
            setShowBadge(true)
        }

        // 5. 应用下载与更新通知渠道
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
