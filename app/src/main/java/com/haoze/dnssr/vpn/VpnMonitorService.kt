package com.haoze.dnssr.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.localizedText

/**
 * VPN 未运行时的前台监控服务。
 *
 * 当 [DnsVpnService] 停止或被系统撤销时启动，常驻通知栏提示用户开启 VPN。
 * 用户点击通知或操作按钮后回到主界面，由主界面继续走连接流程，本服务随即停止。
 */
class VpnMonitorService : Service() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_MONITOR) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        if (!AppSettings.isPersistentNotificationEnabled(this)) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            startForeground(NOTIFICATION_ID, buildStoppedNotification())
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildStoppedNotification()
        startForeground(
            NOTIFICATION_ID,
            notification
        )
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildStoppedNotification(): android.app.Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(
                AppSettings.getNotificationTextStopped(this)
                    .ifBlank { getString(R.string.vpn_disconnected) }
            )
            .setContentIntent(openAppPendingIntent)
            .addAction(R.drawable.ic_play_arrow, getString(R.string.vpn_start), openAppPendingIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                localizedText(this, "谛听 监控"),
                NotificationManager.IMPORTANCE_DEFAULT
            )
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "dns_vpn_monitor_channel"
        private const val NOTIFICATION_ID = 3
        private const val ACTION_STOP_MONITOR = "com.haoze.dnssr.STOP_MONITOR"

        fun startIntent(context: Context): Intent {
            return Intent(context, VpnMonitorService::class.java)
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, VpnMonitorService::class.java).setAction(ACTION_STOP_MONITOR)
        }
    }
}
