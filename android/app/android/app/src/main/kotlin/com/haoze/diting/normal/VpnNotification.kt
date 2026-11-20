package com.haoze.diting.normal

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.automation.AutomationContract
import com.haoze.diting.automation.AutomationReceiver
import com.haoze.diting.platform.NotificationMode
import com.haoze.diting.platform.NotificationSettings
import com.haoze.diting.platform.NotificationStatsLine

object VpnNotification {
    fun build(
        context: Context,
        channelId: String,
        stopAction: String,
    ): Notification {
        val openIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            context,
            1,
            Intent(context, DitingVpnService::class.java).setAction(stopAction),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val pauseIntent = PendingIntent.getBroadcast(
            context,
            2,
            Intent(context, AutomationReceiver::class.java).apply {
                action = AutomationContract.ACTION_PAUSE
                putExtra(AutomationContract.EXTRA_PAUSE_MINUTES, AutomationContract.DEFAULT_PAUSE_MINUTES)
                setPackage(context.packageName)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()

        val status = NotificationSettings.runningText(
            context,
            NotificationMode.NORMAL,
            "运行中",
        )
        val detail = NotificationStatsLine.compose(context, withSpeed = true)
        val body = if (detail == null) status else "$status\n$detail"
        return NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("$label · 普通模式")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .addAction(0, "暂停1小时", pauseIntent)
            .setOngoing(NotificationSettings.persistent(context))
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    fun refresh(
        context: Context,
        channelId: String,
        notificationId: Int,
        stopAction: String,
    ) {
        if (!NotificationSettings.hasLiveItems(context)) return
        rerender(context, channelId, notificationId, stopAction)
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
