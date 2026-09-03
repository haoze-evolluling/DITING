package com.haoze.dnssr.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ForegroundInfo
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.notification.AppNotificationChannels
import com.haoze.dnssr.ui.localizedText

internal class RuleUpdateNotifier(
    private val context: Context,
    private val progressNotificationId: Int
) {
    private val manager = NotificationManagerCompat.from(context)

    init {
        AppNotificationChannels.createAllChannels(context)
    }

    fun foregroundInfo(
        title: String,
        detail: String = context.getString(R.string.operation_preparing),
        current: Int = 0,
        total: Int = 0
    ) = ForegroundInfo(
        progressNotificationId,
        buildProgress(title, detail, current, total),
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    )

    fun showProgress(title: String, detail: String, current: Int = 0, total: Int = 0) {
        manager.notify(progressNotificationId, buildProgress(title, detail, current, total))
    }

    private fun buildProgress(title: String, detail: String, current: Int, total: Int) =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle(localizedText(context, title))
            .setContentText(localizedText(context, detail))
            .setStyle(NotificationCompat.BigTextStyle().bigText(localizedText(context, detail)))
            .setProgress(total.coerceAtLeast(0), current.coerceIn(0, total.coerceAtLeast(0)), total <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(mainPendingIntent())
            .build()

    private fun mainPendingIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        progressNotificationId,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private companion object {
        const val CHANNEL_ID = AppNotificationChannels.CHANNEL_RULE_OPERATIONS
    }
}
