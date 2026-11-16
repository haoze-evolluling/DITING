package com.haoze.diting.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build

/// Foreground-service plumbing shared by the two VPN services: the low-importance channel, the
/// foreground promotion and the compat stop. Kept out of the services so each one only owns its
/// tunnel lifecycle.
internal object VpnServiceForeground {
    fun createChannel(context: Context, channelId: String, name: String, description: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(channelId, name, NotificationManager.IMPORTANCE_LOW)
        channel.description = description
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    /// Android 12+ requires foreground promotion inside onStartCommand, and a throw there is a
    /// crash. The failure is returned so the caller logs it under its own mode scope.
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            service.stopForeground(true)
        }
    }
}
