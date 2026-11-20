package com.haoze.diting.watchdog

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R

object VpnWatchNotification {
    enum class Phase { CHECKING, OCCUPIED, NEEDS_CONSENT }

    private const val REQUEST_OPEN = 2
    private const val REQUEST_STOP = 3

    fun show(
        context: Context,
        channelId: String,
        notificationId: Int,
        modeTitle: String,
        stopIntent: Intent,
        phase: Phase,
    ) {
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (phase == Phase.NEEDS_CONSENT) putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
        }
        val openPending = PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            open,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopPending = PendingIntent.getService(
            context,
            REQUEST_STOP,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        val body = when (phase) {
            Phase.CHECKING -> "VPN 连接已中断，正在检测通道状态"
            Phase.OCCUPIED -> "VPN 通道被其他应用占用，释放后将自动重新连接"
            Phase.NEEDS_CONSENT -> "VPN 通道已空闲，点击重新连接"
        }
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("$label · $modeTitle")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openPending)
            .addAction(0, "停止", stopPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        runCatching {
            context.getSystemService(NotificationManager::class.java)
                ?.notify(notificationId, notification)
        }
    }
}
