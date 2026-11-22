package com.haoze.diting.vpn

import android.content.Context
import com.haoze.diting.engine.Engine
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.tile.QuickSettingsTileUpdater

/**
 * 一种工作模式的运行时状态与持久化标记。
 *
 * 普通模式与简洁模式各持一个实例，偏好容器与运行标记键都保持原值，
 * 因此两种模式的数据互不影响。
 */
internal class VpnRuntime(
    val prefsName: String,
    private val runningKey: String,
) {
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
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getBoolean(runningKey, false)

    fun setPersistedRunning(context: Context, value: Boolean) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(runningKey, value)
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

    companion object {
        const val NORMAL_PREFS = "dns_vpn_prefs"
        const val EXPRESS_PREFS = "express_vpn_prefs"

        val NORMAL = VpnRuntime(NORMAL_PREFS, "vpn_running")

        val EXPRESS = VpnRuntime(EXPRESS_PREFS, "express_vpn_running")
    }
}
