package com.haoze.diting.normal

import android.content.Context
import com.haoze.diting.engine.Engine
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.tile.QuickSettingsTileUpdater

internal object NormalVpnRuntime {
    const val PREFS_NAME = "dns_vpn_prefs"
    private const val KEY_VPN_RUNNING = "vpn_running"

    @Volatile
    var isRunning: Boolean = false

    @Volatile
    var startedAt: Long = 0L

    @Volatile
    var engine: Engine? = null

    @Volatile
    var lastError: String? = null

    @Volatile
    var reclaiming: Boolean = false

    fun isPersistedRunning(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_VPN_RUNNING, false)

    fun setPersistedRunning(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_VPN_RUNNING, value)
            .apply()
        QuickSettingsTileUpdater.requestTileUpdate(context)
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "running" to isRunning,
        "reclaiming" to reclaiming,
        "persisted" to isPersistedRunning(context),
        "error" to lastError,
        "startedAt" to startedAt,
        "stats" to EngineStats.snapshot(engine),
    )

    fun trafficRates(): Map<String, Any?> {
        if (!isRunning) {
            return mapOf("running" to false, "txBps" to 0L, "rxBps" to 0L)
        }
        val (tx, rx) = TrafficRateMonitor.snapshot()
        return mapOf("running" to true, "txBps" to tx, "rxBps" to rx)
    }
}
