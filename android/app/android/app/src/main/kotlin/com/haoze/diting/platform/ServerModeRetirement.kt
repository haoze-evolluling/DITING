package com.haoze.diting.platform

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File

internal object ServerModeRetirement {
    private const val TAG = "ServerModeRetirement"
    private const val SERVER_PREFS = "diting_dns_mode_prefs"
    private const val UI_PREFS = "dns_vpn_prefs"
    private const val NOTIFICATION_PREFS = "notification_settings_prefs"
    private const val WORK_MODE_PREFS = "diting_settings"
    private const val RETIRED_WORK_MODE = "dns"
    private const val SERVER_DASHBOARD_KEY = "server_dashboard_widget_order"
    private const val SERVER_NOTIFICATION_KEY = "default_server_text"
    private const val SERVER_NOTIFICATION_CHANNEL = "channel_dns_mode"

    private val DATABASES = listOf(
        "diting_dns_rules_v2",
        "diting_dns_logs_v2",
        "diting_dns_rules",
        "diting_server_logs",
        "diting_dns_logs",
    )

    @Volatile
    private var ran = false

    fun purge(context: Context) {
        if (ran) return
        ran = true
        runCatching {
            val appContext = context.applicationContext
            clearPreferences(appContext)
            deleteDatabases(appContext)
            deleteRuleIndex(appContext)
            deleteNotificationChannel(appContext)
        }.onFailure { Log.w(TAG, "server-mode retirement cleanup failed", it) }
    }

    private fun clearPreferences(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.deleteSharedPreferences(SERVER_PREFS)
        } else {
            context.getSharedPreferences(SERVER_PREFS, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .commit()
        }
        context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(SERVER_DASHBOARD_KEY)
            .apply()
        context.getSharedPreferences(NOTIFICATION_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(SERVER_NOTIFICATION_KEY)
            .apply()
        val workMode = context.getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
        if (workMode.getString("app_work_mode", null) == RETIRED_WORK_MODE) {
            workMode.edit().remove("app_work_mode").commit()
        }
    }

    private fun deleteDatabases(context: Context) {
        val directory = context.getDatabasePath(DATABASES.first()).parentFile
            ?: File(context.applicationInfo.dataDir, "databases")
        for (name in DATABASES) {
            context.deleteDatabase(name)
            for (suffix in listOf("", "-wal", "-shm", "-journal")) {
                File(directory, "$name$suffix").delete()
            }
        }
    }

    private fun deleteRuleIndex(context: Context) {
        File(File(context.filesDir, "rule-index"), "dns").deleteRecursively()
    }

    private fun deleteNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java)
            ?.deleteNotificationChannel(SERVER_NOTIFICATION_CHANNEL)
    }
}
