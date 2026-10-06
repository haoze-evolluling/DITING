package com.haoze.diting.express.notification

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.notification.NotificationSettingsStore
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.localizedText
import com.haoze.diting.core.dns.DnsProvider

/**
 * Builds foreground service notifications dedicated to Express Mode VPN.
 *
 * Displays Express Mode running status and DNS upstream summary while
 * omitting full-tunnel transfer speed and proxy indicators.
 * Fully compatible with Android 7+ (API 24+) with version branching
 * for NotificationChannel (API < 26).
 */
object ExpressNotificationBuilder {

    const val NOTIFICATION_ID_EXPRESS_VPN = 2001
    const val CHANNEL_EXPRESS_VPN = "diting_express_vpn_channel"

    /**
     * Ensures the notification channel exists on Android 8.0+ (API 26+).
     */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                CHANNEL_EXPRESS_VPN,
                localizedText(context, "极速模式 VPN 服务"),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = localizedText(context, "显示极速模式运行状态与 DNS 提供商")
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * Builds the foreground service notification.
     */
    fun build(
        context: Context,
        activeProviders: List<DnsProvider>,
        activeResolutionMode: DnsResolutionMode
    ): Notification {
        ensureChannel(context)

        val custom = NotificationSettingsStore.getCustomRunningText(context)
        val statusText = if (custom.isNotBlank()) {
            custom
        } else {
            buildDefaultStatusText(context, activeProviders, activeResolutionMode)
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val channelId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            CHANNEL_EXPRESS_VPN
        } else {
            ""
        }

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(statusText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(statusText))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }

        return builder.build()
    }

    internal fun formatStatusText(
        activeProviders: List<DnsProvider>,
        activeResolutionMode: DnsResolutionMode,
        translator: (String) -> String = { it }
    ): String {
        val prefix = translator("极速模式运行中")
        return when {
            activeProviders.size > 1 -> {
                val mode = translator(activeResolutionMode.displayName)
                val count = translator("${activeProviders.size} 个服务商")
                "$prefix · [$mode] $count"
            }
            activeProviders.isNotEmpty() -> {
                val name = translator(activeProviders.first().name)
                "$prefix · $name"
            }
            else -> prefix
        }
    }

    internal fun buildDefaultStatusText(
        context: Context,
        activeProviders: List<DnsProvider>,
        activeResolutionMode: DnsResolutionMode
    ): String = formatStatusText(activeProviders, activeResolutionMode) { localizedText(context, it) }
}
