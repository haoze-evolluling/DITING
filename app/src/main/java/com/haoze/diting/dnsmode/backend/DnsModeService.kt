package com.haoze.diting.dnsmode.backend

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.R
import com.haoze.diting.dnsmode.DnsMainActivity

class DnsModeService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_REFRESH -> {
                refreshNotification()
                return START_STICKY
            }
            ACTION_START -> {
                startForegroundServiceInternal()
                DnsModeManager.onServiceStarted()
            }
            null -> {
                if (DnsModePreferences.isServiceActive(this)) {
                    startForegroundServiceInternal()
                    DnsModeManager.onServiceStarted()
                } else {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        DnsModePreferences.setServiceActive(this, false)
        DnsModeManager.onServiceStopped()
        super.onDestroy()
    }

    private fun startForegroundServiceInternal() {
        val notification = buildForegroundNotification()
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        }.onFailure {
            runCatching {
                startForeground(NOTIFICATION_ID, notification)
            }
        }
    }

    private fun refreshNotification() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildForegroundNotification())
    }

    private fun buildForegroundNotification(): Notification {
        val openAppIntent = Intent(this, DnsMainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, DnsModeService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val activeUpstream = DnsModeManager.getActiveUpstream()
        val contentText = "当前上游: ${activeUpstream.name} (${activeUpstream.address})"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle("谛听 · DNS 模式运行中")
            .setContentText(contentText)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "停止",
                stopPendingIntent
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DNS 模式服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示 DNS 独立代理模式的运行状态"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "channel_dns_mode"
        private const val NOTIFICATION_ID = 2002

        const val ACTION_START = "com.haoze.diting.dnsmode.START"
        const val ACTION_STOP = "com.haoze.diting.dnsmode.STOP"
        const val ACTION_REFRESH = "com.haoze.diting.dnsmode.REFRESH"

        fun startIntent(context: Context): Intent {
            return Intent(context, DnsModeService::class.java).apply {
                action = ACTION_START
            }
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, DnsModeService::class.java).apply {
                action = ACTION_STOP
            }
        }

        fun refreshIntent(context: Context): Intent {
            return Intent(context, DnsModeService::class.java).apply {
                action = ACTION_REFRESH
            }
        }
    }
}
