package com.haoze.diting.vpn

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
import com.haoze.diting.platform.NotificationSettings
import com.haoze.diting.platform.NotificationStatsLine

/** 普通模式与简洁模式共用的常驻通知，差异只来自 [VpnModeProfile]。 */
internal object VpnModeNotification {
    fun build(context: Context, profile: VpnModeProfile): Notification {
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
            Intent(context, profile.serviceClass).setAction(profile.stopAction),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val pauseIntent = PendingIntent.getBroadcast(
            context,
            2,
            Intent(context, AutomationReceiver::class.java).apply {
                action = AutomationContract.ACTION_PAUSE
                putExtra(
                    AutomationContract.EXTRA_PAUSE_MINUTES,
                    AutomationContract.DEFAULT_PAUSE_MINUTES,
                )
                setPackage(context.packageName)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        val status = NotificationSettings.runningText(
            context,
            profile.notificationMode,
            "运行中",
        )
        val detail = NotificationStatsLine.compose(context, withSpeed = profile.showSpeedLine)
        val body = if (detail == null) status else "$status\n$detail"
        val builder = NotificationCompat.Builder(context, profile.channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("$label · ${profile.modeTitle}")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setOngoing(NotificationSettings.persistent(context))
        if (profile.pauseAction) {
            builder.addAction(0, "暂停1小时", pauseIntent)
        }
        return builder.build()
    }

    fun refresh(context: Context, profile: VpnModeProfile) {
        if (!NotificationSettings.hasLiveItems(context)) return
        rerender(context, profile)
    }

    fun rerender(context: Context, profile: VpnModeProfile): Boolean = runCatching {
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return@runCatching false
        manager.notify(profile.notificationId, build(context, profile))
        true
    }.getOrDefault(false)
}
