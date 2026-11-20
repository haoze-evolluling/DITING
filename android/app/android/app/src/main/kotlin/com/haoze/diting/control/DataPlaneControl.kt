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

/// Starts, stops and toggles whichever data plane the current work mode uses, without the Flutter
/// layer. Shared by the quick settings tile, the home screen widget and the automation activity so
/// the three surfaces cannot drift apart.
///
/// The service companions are the only source of truth: every service runs in this process, so a
/// stale static flag cannot outlive a restart the way a persisted one would.
object DataPlaneControl {
    private const val TAG = "DataPlaneControl"
    private const val UI_PREFS = "dns_vpn_prefs"
    private const val WORK_MODE_PREFS = "diting_settings"
    private const val KEY_WORK_MODE = "app_work_mode"
    private const val KEY_INITIAL_AGREEMENT_ACCEPTED = "initial_agreement_accepted"
    private const val KEY_ROOT_TAKEOVER = "root_dns_takeover_enabled"

    const val WORK_MODE_NORMAL = "normal"
    const val WORK_MODE_EXPRESS = "express"
    const val WORK_MODE_SERVER = "server"

    /// Retired value owned by the removed Kotlin server. It is cleaned up by
    /// `ServerModeRetirement` and must never start another mode by accident.
    private const val RETIRED_WORK_MODE_SERVER = "dns"

    /// What a [toggle]/[start]/[stop] call achieved. [NeedsApp] is not a failure: the app owns the
    /// VPN consent dialog and the first Dart-computed start config, so the caller must open it.
    sealed interface Result {
        data object Started : Result
        data object Stopped : Result
        data object NeedsApp : Result
    }

    /// Stored value: `normal` / `express` / `server`; a missing value means normal.
    fun workMode(context: Context): String =
        context.getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WORK_MODE, null)
            ?: WORK_MODE_NORMAL

    /// The first-run agreement gate, shared with the Flutter side.
    fun isAgreementAccepted(context: Context): Boolean =
        context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_INITIAL_AGREEMENT_ACCEPTED, false)

    /// Normal mode's root variant: the same work mode, but no `VpnService` consent is involved.
    fun usesRootTakeover(context: Context): Boolean =
        workMode(context) == WORK_MODE_NORMAL &&
            context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_ROOT_TAKEOVER, false)

    fun isRunning(context: Context): Boolean = when {
        workMode(context) == WORK_MODE_SERVER -> ServerDnsService.isRunning()
        workMode(context) == RETIRED_WORK_MODE_SERVER -> false
        workMode(context) == WORK_MODE_EXPRESS -> ExpressVpnService.isRunning
        usesRootTakeover(context) -> RootDnsService.isRunning
        else -> DitingVpnService.isRunning
    }

    fun toggle(context: Context): Result =
        if (isRunning(context)) stop(context) else start(context)

    fun start(context: Context): Result {
        if (isRunning(context)) return Result.Started
        val mode = workMode(context)
        if (mode == RETIRED_WORK_MODE_SERVER) return Result.NeedsApp
        if (mode == WORK_MODE_SERVER) {
            return if (ServerDnsService.start(context, ServerPreference.preferRoot(context))) {
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

    /// Android 12+ may refuse a foreground-service start from the background (a widget broadcast),
    /// so a rejected start falls back to opening the app rather than silently doing nothing.
    private fun startForeground(context: Context, intent: Intent): Boolean =
        runCatching { ContextCompat.startForegroundService(context, intent) }
            .onFailure { Log.e(TAG, "Failed to start ${workMode(context)} data plane", it) }
            .isSuccess
}
