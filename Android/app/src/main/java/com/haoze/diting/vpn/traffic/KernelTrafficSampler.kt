package com.haoze.diting.vpn.traffic

import android.net.TrafficStats
import java.util.concurrent.ConcurrentHashMap

/**
 * Samples Linux kernel TrafficStats by UID, maintains baseline counters,
 * and calculates adaptive sampling backoff intervals.
 */
internal class KernelTrafficSampler {

    private val kernelBaseline = ConcurrentHashMap<Int, UidBaseline>()

    fun initBaseline(appInfos: Collection<CachedAppInfo>) {
        kernelBaseline.clear()
        for (app in appInfos) {
            val tx = TrafficStats.getUidTxBytes(app.uid)
            val rx = TrafficStats.getUidRxBytes(app.uid)
            if (tx >= 0 && rx >= 0) {
                kernelBaseline[app.uid] = UidBaseline(tx, rx)
            }
        }
    }

    fun clearBaseline() {
        kernelBaseline.clear()
    }

    fun calculateBackoffInterval(idleCycles: Int, isScreenOn: Boolean): Long {
        // Adaptive backoff: the more consecutive zero-delta cycles,
        // the longer the sampling interval (1s -> 3s -> 10s);
        // floored at 5s while the screen is off.
        val backoffMs = when {
            idleCycles < KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF -> 1_000L
            idleCycles < KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF * 2 -> KERNEL_SAMPLE_BACKOFF_STEP_MS
            else -> KERNEL_SAMPLE_MAX_BACKOFF_MS
        }
        return if (isScreenOn) backoffMs else maxOf(KERNEL_SAMPLE_SCREEN_OFF_MIN_MS, backoffMs)
    }

    /**
     * Polls UID traffic stats, detects deltas, and invokes callbacks for apps with or without traffic.
     * Returns a Pair of (totalTxDelta, totalRxDelta).
     */
    fun sampleTraffic(
        appInfos: Collection<CachedAppInfo>,
        onAppDelta: (appInfo: CachedAppInfo, txDelta: Long, rxDelta: Long) -> Unit,
        onAppIdle: (packageName: String) -> Unit
    ): Pair<Long, Long> {
        var totalTxDelta = 0L
        var totalRxDelta = 0L

        for (appInfo in appInfos) {
            val uid = appInfo.uid
            val currentTx = TrafficStats.getUidTxBytes(uid)
            val currentRx = TrafficStats.getUidRxBytes(uid)

            if (currentTx < 0 || currentRx < 0) continue

            val baseline = kernelBaseline.getOrPut(uid) { UidBaseline(currentTx, currentRx) }

            if (currentTx < baseline.tx || currentRx < baseline.rx) {
                // Counter went backwards: device reboot or a UID that was recycled and reassigned.
                baseline.tx = currentTx
                baseline.rx = currentRx
                continue
            }

            val txDelta = currentTx - baseline.tx
            val rxDelta = currentRx - baseline.rx

            baseline.tx = currentTx
            baseline.rx = currentRx

            if (txDelta > 0 || rxDelta > 0) {
                onAppDelta(appInfo, txDelta, rxDelta)
                totalTxDelta += txDelta
                totalRxDelta += rxDelta
            } else {
                onAppIdle(appInfo.packageName)
            }
        }

        return Pair(totalTxDelta, totalRxDelta)
    }

    companion object {
        // Kernel-sampling adaptive backoff: after 8 consecutive zero-delta cycles,
        // 1s -> 3s -> 10s; any detected delta immediately drops back to 1s.
        private const val KERNEL_SAMPLE_IDLE_CYCLES_BEFORE_BACKOFF = 8
        private const val KERNEL_SAMPLE_BACKOFF_STEP_MS = 3_000L
        private const val KERNEL_SAMPLE_MAX_BACKOFF_MS = 10_000L
        // Sampling interval floor while the screen is off: backoff only reduces
        // idle wakeups; with active traffic the off-screen interval stays at 5s or above
        private const val KERNEL_SAMPLE_SCREEN_OFF_MIN_MS = 5_000L
    }
}
