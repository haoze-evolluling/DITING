package com.haoze.dnssr.notification

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.vpn.DnsProvider
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import java.util.Locale

/**
 * 负责构建 VPN 前台服务通知（包含运行状态、出站代理状态以及实时速率）。
 */
object VpnNotificationBuilder {

    const val NOTIFICATION_ID_VPN_SERVICE = 1001

    /**
     * 构建前台服务通知。
     */
    fun build(
        context: Context,
        activeProviders: List<DnsProvider>,
        activeResolutionMode: DnsResolutionMode
    ): Notification {
        val proxyConfig = AppSettings.getOutboundProxyConfig(context)
        val proxyStatus = AppSettings.getOutboundProxyStatus(context)

        // 1. 构建主描述文案
        val primaryText = when {
            proxyConfig.enabled && proxyStatus.first == "error" ->
                localizedText(context, "出站代理不可用 · ${proxyStatus.second.ifBlank { "连接失败" }}")
            proxyConfig.enabled && proxyStatus.first == "connecting" ->
                localizedText(context, "正在连接出站代理")
            else -> {
                val custom = NotificationSettingsStore.getCustomRunningText(context)
                if (custom.isNotBlank()) {
                    custom
                } else {
                    buildDefaultStatusText(context, activeProviders, activeResolutionMode)
                }
            }
        }

        // 2. 构建速率文本
        val speedText = if (NotificationSettingsStore.isTrafficSpeedEnabled(context)) {
            val snapshot = TrafficStatsManager.uiSnapshot.value
            val formatted = formatTrafficSpeed(snapshot.totalTxSpeedBps, snapshot.totalRxSpeedBps)
            "\n$formatted"
        } else {
            ""
        }

        val fullContentText = primaryText + speedText

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, AppNotificationChannels.CHANNEL_VPN_SERVICE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(fullContentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(fullContentText))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun buildDefaultStatusText(
        context: Context,
        activeProviders: List<DnsProvider>,
        activeResolutionMode: DnsResolutionMode
    ): String {
        return when {
            activeProviders.size > 1 -> {
                val mode = localizedText(context, activeResolutionMode.displayName)
                val count = localizedText(context, "${activeProviders.size} 个服务商")
                "${localizedText(context, "已连接")} · [$mode] $count"
            }
            activeProviders.isNotEmpty() -> {
                val name = localizedText(context, activeProviders.first().name)
                "${localizedText(context, "已连接")} · $name"
            }
            else -> localizedText(context, "已连接")
        }
    }

    /**
     * 格式化实时网速文本。
     */
    fun formatTrafficSpeed(txBps: Long, rxBps: Long): String {
        fun fmt(b: Long): String = when {
            b >= 1024 * 1024 -> String.format(Locale.US, "%.1f MB/s", b / (1024.0 * 1024.0))
            b >= 1024 -> String.format(Locale.US, "%.0f KB/s", b / 1024.0)
            else -> "$b B/s"
        }
        return "↑ ${fmt(txBps)}  ↓ ${fmt(rxBps)}"
    }
}
