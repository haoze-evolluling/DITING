package com.haoze.diting.express

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.platform.NotificationMode
import com.haoze.diting.platform.NotificationSettings
import com.haoze.diting.platform.NotificationStatsLine

object ExpressNotification {
    fun build(context: Context, channelId: String, stopAction: String): Notification {
        val openIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            context,
            1,
            Intent(context, ExpressVpnService::class.java).setAction(stopAction),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        val status = NotificationSettings.runningText(
            context,
            NotificationMode.EXPRESS,
            "运行中",
        )
        val detail = NotificationStatsLine.compose(context, withSpeed = false)
        val body = if (detail == null) status else "$status\n$detail"
        return NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("$label · 极速模式")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    fun rerender(
        context: Context,
        channelId: String,
        notificationId: Int,
        stopAction: String,
    ): Boolean = runCatching {
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return@runCatching false
        manager.notify(notificationId, build(context, channelId, stopAction))
        true
    }.getOrDefault(false)
}
