package com.haoze.dnssr.update

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R

class AppUpdateNotifier(private val context: Context) {
    private val notificationManager = NotificationManagerCompat.from(context)

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.getString(R.string.app_update_channel), NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    fun showProgress(update: AppUpdateInfo, downloadedBytes: Long, totalBytes: Long) {
        if (!canPostNotifications()) return
        val percentage = if (totalBytes > 0L) ((downloadedBytes * 100L) / totalBytes).toInt().coerceIn(0, 100) else 0
        val detail = if (totalBytes > 0L) {
            "$percentage%  ${formatAppUpdateBytes(downloadedBytes)} / ${formatAppUpdateBytes(totalBytes)}"
        } else {
            context.getString(R.string.app_update_downloaded, formatAppUpdateBytes(downloadedBytes))
        }
        notificationManager.notify(
            NOTIFICATION_ID,
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.dns_svgrepo_com)
                .setContentTitle(context.getString(R.string.app_update_downloading, update.version))
                .setContentText(detail)
                .setProgress(100, percentage, totalBytes <= 0L)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(mainPendingIntent())
                .build()
        )
    }

    fun showCompleted(update: AppUpdateInfo) {
        if (!canPostNotifications()) return
        notificationManager.notify(
            NOTIFICATION_ID,
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.dns_svgrepo_com)
                .setContentTitle(context.getString(R.string.app_update_download_complete, update.version))
                .setContentText(context.getString(R.string.app_update_install))
                .setProgress(0, 0, false)
                .setAutoCancel(true)
                .setContentIntent(mainPendingIntent())
                .build()
        )
    }

    fun clear() = notificationManager.cancel(NOTIFICATION_ID)

    private fun canPostNotifications(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun mainPendingIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        NOTIFICATION_ID,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private companion object {
        const val CHANNEL_ID = "app_update"
        const val NOTIFICATION_ID = 41018
    }
}

internal fun formatAppUpdateBytes(bytes: Long): String {
    if (bytes < 1024L) return "$bytes B"
    val units = arrayOf("KB", "MB", "GB")
    var value = bytes.toDouble()
    var unitIndex = -1
    while (value >= 1024.0 && unitIndex < units.lastIndex) {
        value /= 1024.0
        unitIndex++
    }
    return "%.1f %s".format(java.util.Locale.US, value, units[unitIndex])
}
