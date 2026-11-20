package com.haoze.diting.root

import android.content.Context
import android.net.TrafficStats
import android.os.SystemClock
import com.haoze.diting.engine.Engine
import com.haoze.diting.log.EngineStats
import com.haoze.diting.tile.QuickSettingsTileUpdater

internal object RootDnsRuntime {
    const val PREFS_NAME = "dns_root_prefs"
    private const val KEY_RUNNING = "root_dns_running"
    private const val KEY_RULES_INSTALLED = "root_dns_rules_installed"
    private const val KEY_PRIVATE_DNS_CHANGED = "root_dns_private_dns_changed"
    private const val KEY_PRIVATE_DNS_PREVIOUS = "root_dns_private_dns_previous"

    @Volatile
    var running: Boolean = false

    @Volatile
    var starting: Boolean = false

    @Volatile
    var error: String? = null

    @Volatile
    var startedAt: Long = 0L

    @Volatile
    var port: Int = 0

    @Volatile
    var engine: Engine? = null

    fun status(context: Context): Map<String, Any?> = mapOf(
        "running" to running,
        "starting" to starting,
        "reclaiming" to false,
        "persisted" to isPersistedRunning(context),
        "error" to error,
        "startedAt" to startedAt,
        "port" to port,
        "stats" to EngineStats.snapshot(engine),
    )

    fun begin() {
        running = false
        starting = true
        error = null
        startedAt = 0L
        port = 0
    }

    fun ready(engine: Engine, port: Int) {
        this.engine = engine
        running = true
        starting = false
        error = null
        startedAt = System.currentTimeMillis()
        this.port = port
    }

    fun failed(message: String) {
        running = false
        starting = false
        error = message
        startedAt = 0L
        port = 0
    }

    fun stopped() {
        running = false
        starting = false
        startedAt = 0L
        port = 0
        engine = null
    }


    fun isPersistedRunning(context: Context): Boolean =
        prefs(context).getBoolean(KEY_RUNNING, false)

    fun setPersistedRunning(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_RUNNING, value).apply()
        QuickSettingsTileUpdater.requestTileUpdate(context)
    }

    fun rulesInstalled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_RULES_INSTALLED, false)

    fun markRulesInstalled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_RULES_INSTALLED, value).commit()
    }

    fun rememberPrivateDns(context: Context, previous: String) {
        prefs(context).edit()
            .putBoolean(KEY_PRIVATE_DNS_CHANGED, true)
            .putString(KEY_PRIVATE_DNS_PREVIOUS, previous)
            .commit()
    }

    fun previousPrivateDns(context: Context): String? {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_PRIVATE_DNS_CHANGED, false)) return null
        return prefs.getString(KEY_PRIVATE_DNS_PREVIOUS, null)
    }

    fun clearPrivateDns(context: Context) {
        prefs(context).edit()
            .remove(KEY_PRIVATE_DNS_CHANGED)
            .remove(KEY_PRIVATE_DNS_PREVIOUS)
            .commit()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

internal object RootDnsTraffic {
    private var lastTx = 0L
    private var lastRx = 0L
    private var lastAt = 0L

    fun reset() {
        lastTx = 0L
        lastRx = 0L
        lastAt = 0L
    }

    fun snapshot(running: Boolean): Map<String, Any?> {
        if (!running) {
            reset()
            return mapOf("running" to false, "txBps" to 0L, "rxBps" to 0L)
        }
        val now = SystemClock.elapsedRealtime()
        val tx = TrafficStats.getTotalTxBytes()
        val rx = TrafficStats.getTotalRxBytes()
        if (tx < 0 || rx < 0) {
            return mapOf("running" to true, "txBps" to 0L, "rxBps" to 0L)
        }
        val previousAt = lastAt
        val elapsedMs = now - previousAt
        val animate = previousAt != 0L && elapsedMs in 1..MAX_INTERVAL_MS && tx >= lastTx && rx >= lastRx
        val txBps = if (animate) (tx - lastTx) * 1000L / elapsedMs else 0L
        val rxBps = if (animate) (rx - lastRx) * 1000L / elapsedMs else 0L
        lastTx = tx
        lastRx = rx
        lastAt = now
        return mapOf("running" to true, "txBps" to txBps, "rxBps" to rxBps)
    }

    private const val MAX_INTERVAL_MS = 30_000L
}
