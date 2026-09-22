package com.haoze.diting.vpn.traffic

import java.util.concurrent.atomic.AtomicLong

/**
 * Represents traffic statistics for a single application.
 */
data class AppTrafficItem(
    val packageName: String,
    val appName: String,
    val isSystemApp: Boolean,
    val sessionTxBytes: Long,
    val sessionRxBytes: Long,
    val todayTxBytes: Long,
    val todayRxBytes: Long,
    val currentTxSpeedBps: Long,
    val currentRxSpeedBps: Long
) {
    val sessionTotalBytes: Long get() = sessionTxBytes + sessionRxBytes
    val todayTotalBytes: Long get() = todayTxBytes + todayRxBytes
    val currentTotalSpeedBps: Long get() = currentTxSpeedBps + currentRxSpeedBps
}

/**
 * UI snapshot containing global traffic speed, totals, and per-app traffic items.
 */
data class TrafficStatsUiSnapshot(
    val isRunning: Boolean = false,
    val isGoTunnelActive: Boolean = false,
    val totalTxSpeedBps: Long = 0L,
    val totalRxSpeedBps: Long = 0L,
    val sessionTxBytes: Long = 0L,
    val sessionRxBytes: Long = 0L,
    val todayTxBytes: Long = 0L,
    val todayRxBytes: Long = 0L,
    val sessionStartTimeMs: Long = 0L,
    val appStatsList: List<AppTrafficItem> = emptyList(),
    val updatedAt: Long = 0L
) {
    val sessionTotalBytes: Long get() = sessionTxBytes + sessionRxBytes
    val todayTotalBytes: Long get() = todayTxBytes + todayRxBytes
    val totalSpeedBps: Long get() = totalTxSpeedBps + totalRxSpeedBps
}

internal class CachedAppInfo(
    val uid: Int,
    val packageName: String,
    val appName: String,
    val isSystemApp: Boolean
)

internal class UidBaseline(
    var tx: Long,
    var rx: Long
)

internal class AppByteCounters {
    val tx = AtomicLong(0L)
    val rx = AtomicLong(0L)
}

internal class AppSpeedEma {
    var txSpeed = 0.0
    var rxSpeed = 0.0
    var idleSeconds = 0.0
}

internal class PendingDelta(
    val packageName: String,
    val appName: String
) {
    val tx = AtomicLong(0L)
    val rx = AtomicLong(0L)
}
