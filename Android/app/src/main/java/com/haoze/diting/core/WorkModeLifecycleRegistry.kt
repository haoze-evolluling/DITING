package com.haoze.diting.core

import android.content.Context
import android.content.Intent
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * Registry for coordinating lifecycle operations across work modes without direct mutual imports.
 */
object WorkModeLifecycleRegistry {
    @Volatile
    var stopNormalMode: (Context) -> Unit = {}

    @Volatile
    var stopServerMode: (Context) -> Unit = {}

    @Volatile
    var stopExpressMode: (Context) -> Unit = {}

    @Volatile
    var updateNormalFloatingLogAppState: (Context, Boolean) -> Unit = { ctx, fg ->
        val sp = ctx.getSharedPreferences("system_settings", Context.MODE_PRIVATE)
        sp.edit().putBoolean("main_activity_foreground", fg).apply()
        if (VpnStateRegistry.isNormalRunning(ctx)) {
            val intent = Intent().setClassName(ctx.packageName, "${ctx.packageName}.normal.DnsVpnService")
                .setAction("com.haoze.diting.vpn.ACTION_FLOATING_LOG_APP_STATE")
                .putExtra("app_foreground", fg)
            runCatching { ctx.startService(intent) }
        }
    }

    fun stopOtherModes(context: Context, activeMode: AppWorkMode) {
        when (activeMode) {
            AppWorkMode.NORMAL -> {
                stopServerMode(context)
                stopExpressMode(context)
            }
            AppWorkMode.EXPRESS -> {
                stopNormalMode(context)
                stopServerMode(context)
            }
            AppWorkMode.DNS -> {
                stopNormalMode(context)
                stopExpressMode(context)
            }
        }
    }
}
