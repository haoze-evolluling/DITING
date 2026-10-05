package com.haoze.diting.express

import android.content.Context
import android.util.Log

/**
 * Dedicated DNS settings refresher for Express Mode.
 *
 * Sends [ExpressVpnIntents.REFRESH_CONFIG] or [ExpressVpnIntents.SYNC_RULES]
 * to [ExpressVpnService] when DNS settings or domain rules are updated.
 */
object ExpressSettingsRefresher {
    private const val TAG = "ExpressSettingsRefresh"

    fun refreshIfRunning(
        context: Context,
        reason: String = "settings_changed"
    ) {
        val appContext = context.applicationContext
        if (!ExpressVpnController.isRunning(appContext)) return

        runCatching {
            appContext.startService(ExpressVpnIntents.refreshConfigIntent(appContext, reason))
        }.onFailure { error ->
            Log.w(TAG, "Failed to send express config refresh intent", error)
        }
    }

    fun syncRulesIfRunning(context: Context) {
        val appContext = context.applicationContext
        if (!ExpressVpnController.isRunning(appContext)) return

        runCatching {
            appContext.startService(ExpressVpnIntents.syncRulesIntent(appContext))
        }.onFailure { error ->
            Log.w(TAG, "Failed to send express rule sync intent", error)
        }
    }

    fun clearCacheIfRunning(context: Context) {
        val appContext = context.applicationContext
        ExpressVpnController.clearCache(appContext)
    }
}
