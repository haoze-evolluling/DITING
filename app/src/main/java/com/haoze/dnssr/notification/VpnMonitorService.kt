package com.haoze.dnssr.notification

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.vpn.DnsVpnService

/**
 * 当 VPN 未运行时在通知栏常驻展示连接快捷入口的前台监控服务。
 */
class VpnMonitorService : Service() {

    override fun onCreate() {
        super.onCreate()
        AppNotificationChannels.createAllChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_MONITOR) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        // 校验是否启用及是否持有通知权限与 VPN 运行状态
        if (!NotificationSettingsStore.isPersistentNotificationEnabled(this) ||
            !NotificationPermissionHelper.hasPermission(this) ||
            DnsVpnService.isRunning(this)
        ) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildStoppedNotification()
        try {
            startForeground(NOTIFICATION_ID_VPN_MONITOR, notification)
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildStoppedNotification(): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            1,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val customText = NotificationSettingsStore.getCustomStoppedText(this)
        val contentText = if (customText.isNotBlank()) {
            customText
        } else {
            getString(R.string.vpn_disconnected)
        }

        return NotificationCompat.Builder(this, AppNotificationChannels.CHANNEL_VPN_MONITOR)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(contentText)
            .setContentIntent(openAppPendingIntent)
            .addAction(R.drawable.ic_play_arrow, getString(R.string.vpn_start), openAppPendingIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        const val NOTIFICATION_ID_VPN_MONITOR = 1002
        private const val ACTION_STOP_MONITOR = "com.haoze.dnssr.notification.STOP_MONITOR"

        fun startIntent(context: Context): Intent {
            return Intent(context, VpnMonitorService::class.java)
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, VpnMonitorService::class.java).setAction(ACTION_STOP_MONITOR)
        }
    }
}
