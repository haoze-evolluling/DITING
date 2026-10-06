package com.haoze.diting.core

import android.content.Context
import android.content.Intent
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * Registry for coordinating lifecycle operations across work modes without direct mutual imports.
 */
object WorkModeLifecycleRegistry {
    @Volatile
    var startNormalMode: (Context) -> Unit = { ctx ->
        val intent = Intent().setClassName(ctx.packageName, "${ctx.packageName}.normal.DnsVpnService")
        runCatching { androidx.core.content.ContextCompat.startForegroundService(ctx, intent) }
    }

    @Volatile
    var stopNormalMode: (Context) -> Unit = { ctx ->
        if (VpnStateRegistry.isNormalRunning(ctx)) {
            val intent = Intent().setClassName(ctx.packageName, "${ctx.packageName}.normal.DnsVpnService")
                .setAction("com.haoze.diting.STOP_VPN")
            runCatching { ctx.startService(intent) }
        }
    }

    @Volatile
    var stopServerMode: (Context) -> Unit = { ctx ->
        val intent = Intent().setClassName(ctx.packageName, "${ctx.packageName}.server.backend.DnsModeService")
            .setAction("com.haoze.diting.server.STOP")
        runCatching { ctx.startService(intent) }
    }

    @Volatile
    var stopExpressMode: (Context) -> Unit = { ctx ->
        if (VpnStateRegistry.isExpressRunning(ctx)) {
            val intent = Intent().setClassName(ctx.packageName, "${ctx.packageName}.express.ExpressVpnService")
                .setAction("com.haoze.diting.express.STOP_VPN")
            runCatching { ctx.startService(intent) }
        }
    }

    @Volatile
    var updateNormalFloatingLogAppState: (Context, Boolean) -> Unit = { ctx, fg ->
        val sp = ctx.getSharedPreferences("system_settings", Context.MODE_PRIVATE)
        sp.edit().putBoolean("main_activity_foreground", fg).apply()
        if (VpnStateRegistry.isNormalRunning(ctx)) {
            val intent = Intent().setClassName(ctx.packageName, "${ctx.packageName}.normal.DnsVpnService")
                .setAction("com.haoze.diting.FLOATING_LOG_APP_STATE")
                .putExtra("app_foreground", fg)
            runCatching { ctx.startService(intent) }
        }
    }

    fun refreshFloatingLogOverlay(context: Context) {
        if (VpnStateRegistry.isExpressRunning(context)) {
            val intent = Intent().setClassName(context.packageName, "${context.packageName}.express.ExpressVpnService")
                .setAction("com.haoze.diting.express.REFRESH_FLOATING_LOG")
            runCatching { context.startService(intent) }
        }
        if (VpnStateRegistry.isNormalRunning(context)) {
            val intent = Intent().setClassName(context.packageName, "${context.packageName}.normal.DnsVpnService")
                .setAction("com.haoze.diting.REFRESH_FLOATING_LOG")
            runCatching { context.startService(intent) }
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
