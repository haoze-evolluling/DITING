package com.haoze.dnssr.notification

import android.content.Context
import android.os.PowerManager
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Lifecycle-safe, screen-state-aware sampler for transfer speed changes, used
 * when the speed readout is enabled in the notification.
 */
class VpnSpeedMonitor(private val context: Context) {

    private var monitorJob: Job? = null

    /**
     * Starts the coroutine that watches for speed changes.
     * @param scope the CoroutineScope to run in (usually the DnsVpnService serviceScope)
     * @param isVpnActive predicate indicating whether the VPN is still active
     * @param onSpeedChanged callback fired whenever the speed changes materially
     */
    fun start(
        scope: CoroutineScope,
        isVpnActive: () -> Boolean,
        onSpeedChanged: () -> Unit
    ) {
        stop()
        if (!NotificationSettingsStore.isTrafficSpeedEnabled(context)) return

        monitorJob = scope.launch {
            val initialSnap = TrafficStatsManager.uiSnapshot.value
            var lastFormattedSpeed = VpnNotificationBuilder.formatTrafficSpeed(
                initialSnap.totalTxSpeedBps,
                initialSnap.totalRxSpeedBps
            )
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager

            while (isActive && isVpnActive()) {
                val isScreenOn = powerManager?.isInteractive ?: true
                if (!isScreenOn) {
                    delay(SCREEN_OFF_POLL_INTERVAL_MS)
                    continue
                }

                delay(SCREEN_ON_SAMPLE_INTERVAL_MS)

                val snap = TrafficStatsManager.uiSnapshot.value
                val formatted = VpnNotificationBuilder.formatTrafficSpeed(snap.totalTxSpeedBps, snap.totalRxSpeedBps)
                if (formatted != lastFormattedSpeed) {
                    lastFormattedSpeed = formatted
                    onSpeedChanged()
                }
            }
        }
    }

    /**
     * Stops watching for speed changes.
     */
    fun stop() {
        monitorJob?.cancel()
        monitorJob = null
    }

    companion object {
        private const val SCREEN_ON_SAMPLE_INTERVAL_MS = 2000L
        private const val SCREEN_OFF_POLL_INTERVAL_MS = 15000L
    }
}
