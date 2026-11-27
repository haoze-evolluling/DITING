package com.haoze.diting.server

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R

/** 服务器前台服务的通知样式；状态文本跟随 [ServerProcessState] 实时变化。 */
object ServerNotification {
    const val CHANNEL_ID = "channel_server"
    const val NOTIFICATION_ID = 5301

    fun text(context: Context): String {
        val state = ServerProcessState.snapshot()
        if (state["restarting"] == true) {
            return context.getString(R.string.server_notification_restarting)
        }
        if (state["starting"] == true) {
            return context.getString(R.string.server_notification_starting)
        }
        if (state["running"] != true) {
            val error = state["error"] as? String
            return error ?: context.getString(R.string.server_notification_stopped)
        }
        val root = state["root"] as? Boolean == true
        val port = (state["port"] as? Number)?.toInt() ?: 1053
        return context.getString(
            if (root) R.string.server_notification_running_root
            else R.string.server_notification_running,
            port,
        )
    }

    fun build(context: Context, text: String): Notification {
        val open = PendingIntent.getActivity(
            context,
            10,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            context,
            11,
            Intent(context, ServerDnsService::class.java).setAction(ServerDnsService.ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.server_notification_title))
            .setContentText(text)
            .setContentIntent(open)
            .addAction(0, context.getString(R.string.server_notification_stop), stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}
