package com.haoze.dnssr.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ForegroundInfo
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.localizedText

internal class RuleUpdateNotifier(
    private val context: Context,
    private val progressNotificationId: Int
) {
    private val manager = NotificationManagerCompat.from(context)

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.getString(R.string.rule_update_channel), NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    fun foregroundInfo(
        title: String,
        detail: String = context.getString(R.string.operation_preparing)
    ) = ForegroundInfo(
        progressNotificationId,
        buildProgress(title, detail),
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    )

    fun showProgress(title: String, detail: String) {
        manager.notify(progressNotificationId, buildProgress(title, detail))
    }

    private fun buildProgress(title: String, detail: String) =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.dns_svgrepo_com)
            .setContentTitle(localizedText(context, title))
            .setContentText(localizedText(context, detail))
            .setStyle(NotificationCompat.BigTextStyle().bigText(localizedText(context, detail)))
            .setProgress(0, 0, true)
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
        const val CHANNEL_ID = "rule_operations"
    }
}
