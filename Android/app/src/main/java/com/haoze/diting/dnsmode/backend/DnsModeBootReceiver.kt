package com.haoze.diting.dnsmode.backend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeStore

/**
 * Restores the LAN DNS server after a reboot when the user left the DNS mode
 * service running, so LAN devices can keep resolving without re-opening the app.
 */
class DnsModeBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (WorkModeStore.getAppWorkMode(context) != AppWorkMode.DNS) return
        if (!DnsModePreferences.isServiceActive(context)) return
        runCatching {
            ContextCompat.startForegroundService(context, DnsModeService.startIntent(context))
        }.onFailure { Log.w(TAG, "Failed to restart DNS mode service after boot", it) }
    }

    companion object {
        private const val TAG = "DnsModeBootReceiver"
    }
}
