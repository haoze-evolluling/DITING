package com.haoze.diting.control

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.root.RootDnsService
import com.haoze.diting.server.ServerDnsService
import com.haoze.diting.server.ServerPreference

object DataPlaneControl {
    private const val TAG = "DataPlaneControl"
    private const val UI_PREFS = "dns_vpn_prefs"
    private const val WORK_MODE_PREFS = "diting_settings"
    private const val KEY_WORK_MODE = "app_work_mode"
    private const val KEY_INITIAL_AGREEMENT_ACCEPTED = "initial_agreement_accepted"
    private const val KEY_ROOT_TAKEOVER = "root_dns_takeover_enabled"
    private const val KEY_AUTO_START_ON_BOOT = "auto_start_on_boot_enabled"

    const val WORK_MODE_NORMAL = "normal"
    const val WORK_MODE_EXPRESS = "express"
    const val WORK_MODE_SERVER = "server"

    private const val RETIRED_WORK_MODE_SERVER = "dns"

    sealed interface Result {
        data object Started : Result
        data object Stopped : Result
        data object NeedsApp : Result
    }

    fun workMode(context: Context): String =
        context.getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WORK_MODE, null)
            ?: WORK_MODE_NORMAL

    fun isAgreementAccepted(context: Context): Boolean =
        context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_INITIAL_AGREEMENT_ACCEPTED, false)

    fun autoStartOnBootEnabled(context: Context): Boolean =
        context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTO_START_ON_BOOT, false)

    /**
     * Root 免 VPN 接管是否生效。
     *
     * 只有简洁模式支持它；普通模式固定走全隧道，服务器模式另有自己的数据面，
     * 两者都不参与这里。
     */
    fun usesRootTakeover(context: Context): Boolean =
        workMode(context) == WORK_MODE_EXPRESS &&
            context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ROOT_TAKEOVER, false)

    fun isRunning(context: Context): Boolean = when {
        workMode(context) == WORK_MODE_SERVER -> ServerDnsService.isRunning()
        workMode(context) == RETIRED_WORK_MODE_SERVER -> false
        usesRootTakeover(context) -> RootDnsService.isRunning
        workMode(context) == WORK_MODE_EXPRESS -> ExpressVpnService.isRunning
        else -> DitingVpnService.isRunning
    }

    fun toggle(context: Context): Result =
        if (isRunning(context)) stop(context) else start(context)

    fun start(context: Context): Result {
        if (isRunning(context)) return Result.Started
        val mode = workMode(context)
        if (mode == RETIRED_WORK_MODE_SERVER) return Result.NeedsApp
        if (mode == WORK_MODE_SERVER) {
            return if (
                ServerDnsService.start(
                    context,
                    ServerPreference.preferRoot(context),
                    null,
                )
            ) {
                Result.Started
            } else {
                Result.NeedsApp
            }
        }
        if (usesRootTakeover(context)) {
            val intent = RootDnsService.restoreIntent(context) ?: return Result.NeedsApp
            return if (startForeground(context, intent)) Result.Started else Result.NeedsApp
        }
        if (VpnService.prepare(context) != null) {
            return Result.NeedsApp
        }
        val intent: Intent = when (mode) {
            WORK_MODE_EXPRESS -> ExpressVpnService.restoreIntent(context)
            else -> DitingVpnService.restoreIntent(context)
        } ?: return Result.NeedsApp
        return if (startForeground(context, intent)) Result.Started else Result.NeedsApp
    }

    fun stop(context: Context): Result {
        if (!isRunning(context)) return Result.Stopped
        if (workMode(context) == WORK_MODE_SERVER) {
            return if (ServerDnsService.stop(context)) Result.Stopped else Result.NeedsApp
        }
        if (usesRootTakeover(context)) {
            return if (RootDnsService.stop(context)) Result.Stopped else Result.NeedsApp
        }
        val intent: Intent = when (workMode(context)) {
            WORK_MODE_EXPRESS -> ExpressVpnService.stopIntent(context)
            else -> DitingVpnService.stopIntent(context)
        }
        return if (runCatching { context.startService(intent) }.isSuccess) {
            Result.Stopped
        } else {
            Result.NeedsApp
        }
    }

    private fun startForeground(context: Context, intent: Intent): Boolean =
        runCatching { ContextCompat.startForegroundService(context, intent) }
            .onFailure { Log.e(TAG, "Failed to start ${workMode(context)} data plane", it) }
            .isSuccess
}
