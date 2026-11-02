package com.haoze.diting.server

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/// Restarts the LAN DNS server after a reboot when the user left server mode running, so LAN
/// devices keep resolving without re-opening the app. The service stores its last start
/// configuration, because the extras of the original intent do not survive a reboot.
class DnsModeBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // MY_PACKAGE_REPLACED covers an in-app update, which also kills the service.
        val actionable = intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        if (!actionable) return
        if (workMode(context) != WORK_MODE_DNS) return
        if (!DitingDnsServerService.isServiceActive(context)) return
        val restart = DitingDnsServerService.restoreIntent(context)
        if (restart == null) {
            Log.w(TAG, "server mode was active but no start config was stored")
            return
        }
        runCatching { ContextCompat.startForegroundService(context, restart) }
            .onFailure { Log.w(TAG, "Failed to restart server mode service after boot", it) }
    }

    /// The legacy `app_work_mode` value; server mode is stored as `dns`.
    private fun workMode(context: Context): String? = runCatching {
        context.getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WORK_MODE, null)
    }.getOrNull()

    companion object {
        private const val TAG = "DnsModeBootReceiver"
        private const val WORK_MODE_PREFS = "diting_settings"
        private const val KEY_WORK_MODE = "app_work_mode"
        private const val WORK_MODE_DNS = "dns"
    }
}
