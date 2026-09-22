package com.haoze.diting.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import android.util.Log
import com.haoze.diting.vpn.traffic.TrafficStatsManager

/**
 * Screen-state-driven power optimization while the screen is off:
 * - TrafficStatsManager pauses snapshot publishing (counters keep accumulating);
 * - The Go traffic-stats tick runs every 1s with the screen on and every
 *   10s with the screen off, so totals are never lost between aggregations.
 */
class DnsVpnPowerOptimizer(
    private val context: Context,
    private val getGoInspectionTunnel: () -> GoInspectionTunnel?
) {
    private var screenStateReceiverRegistered = false

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> onScreenStateChanged(interactive = true)
                Intent.ACTION_SCREEN_OFF -> onScreenStateChanged(interactive = false)
            }
        }
    }

    fun register() {
        if (!screenStateReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_SCREEN_ON).apply {
                addAction(Intent.ACTION_SCREEN_OFF)
            }
            runCatching { context.registerReceiver(screenStateReceiver, filter) }
                .onFailure { Log.w(TAG, "Failed to register screen state receiver", it) }
            screenStateReceiverRegistered = true
        }
        // Re-sync to the current screen state on every VPN start (this also
        // covers the tunnel rebuild caused by an exclusion-list refresh: a
        // freshly created Go tracker needs the correct initial tick interval)
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        onScreenStateChanged(powerManager?.isInteractive ?: true)
    }

    fun unregister() {
        if (!screenStateReceiverRegistered) return
        screenStateReceiverRegistered = false
        runCatching { context.unregisterReceiver(screenStateReceiver) }
    }

    private fun onScreenStateChanged(interactive: Boolean) {
        TrafficStatsManager.setScreenInteractive(interactive)
        getGoInspectionTunnel()?.setTrafficTickIntervalMs(
            if (interactive) TRAFFIC_TICK_INTERVAL_SCREEN_ON_MS else TRAFFIC_TICK_INTERVAL_SCREEN_OFF_MS
        )
    }

    companion object {
        private const val TAG = "DnsVpnPowerOptimizer"
        const val TRAFFIC_TICK_INTERVAL_SCREEN_ON_MS = 1_000L
        const val TRAFFIC_TICK_INTERVAL_SCREEN_OFF_MS = 10_000L
    }
}
