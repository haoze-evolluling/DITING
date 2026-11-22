package com.haoze.diting.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build

internal object VpnServiceForeground {
    fun createChannel(context: Context, channelId: String, name: String, description: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(channelId, name, NotificationManager.IMPORTANCE_LOW)
        channel.description = description
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    fun promote(service: Service, notificationId: Int, notification: Notification): Throwable? =
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                service.startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                service.startForeground(notificationId, notification)
            }
            null
        } catch (t: Throwable) {
            t
        }

    fun stop(service: Service) {
        service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
    }
}
