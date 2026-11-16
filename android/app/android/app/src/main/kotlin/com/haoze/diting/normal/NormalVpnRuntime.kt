package com.haoze.diting.normal

import android.content.Context
import com.haoze.diting.engine.Engine
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.tile.QuickSettingsTileUpdater

/// Mutable runtime state, the persisted running flag and the status snapshots of the full
/// tunnel. `DitingVpnService` keeps the public facade and delegates here, so the service itself
/// only owns the Android lifecycle and the tunnel start/stop orchestration.
internal object NormalVpnRuntime {
    /// `dns_vpn_prefs`: shared with the Dart settings page and the retained log window.
    const val PREFS_NAME = "dns_vpn_prefs"
    private const val KEY_VPN_RUNNING = "vpn_running"

    @Volatile
    var isRunning: Boolean = false

    /// Epoch millis of the last successful start; 0 while stopped. The UI process can be
    /// recreated at any time, so the only trustworthy origin for the uptime figure is here.
    @Volatile
    var startedAt: Long = 0L

    /// Engine of the current run; read-only handle for the diagnostics channel.
    @Volatile
    var engine: Engine? = null

    @Volatile
    var lastError: String? = null

    /// Displaced by another VPN and waiting to reconnect; [isRunning] is false meanwhile.
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
        // The tile lives in another UI surface; it only repaints when told to re-read.
        QuickSettingsTileUpdater.requestTileUpdate(context)
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "running" to isRunning,
        "reclaiming" to reclaiming,
        "persisted" to isPersistedRunning(context),
        "error" to lastError,
        // Milliseconds since the tunnel came up; Dart uses it instead of its own clock.
        "startedAt" to startedAt,
        "stats" to EngineStats.snapshot(engine),
    )

    /// Second-resolution TX/RX rates; zeros while stopped, or the last tick if racing the stop
    fun trafficRates(): Map<String, Any?> {
        if (!isRunning) {
            return mapOf("running" to false, "txBps" to 0L, "rxBps" to 0L)
        }
        val (tx, rx) = TrafficRateMonitor.snapshot()
        return mapOf("running" to true, "txBps" to tx, "rxBps" to rx)
    }
}
