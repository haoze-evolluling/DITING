package com.haoze.diting.log

/// Second-resolution rates for the notification, from the deltas TrafficIngest parses; a singleton.
object TrafficRateMonitor {
    private var lastTx = 0L
    private var lastRx = 0L
    private var lastAtMs = 0L

    @Volatile
    private var txBps = 0L

    @Volatile
    private var rxBps = 0L

    fun onTick(tx: Long, rx: Long) {
        val now = System.currentTimeMillis()
        val previous = lastAtMs
        if (previous > 0) {
            val elapsed = now - previous
            if (elapsed <= 0) return
            // Divide by the real interval: a late callback delivers a double-sized delta.
            txBps = tx * 1000 / elapsed
            rxBps = rx * 1000 / elapsed
            lastTx = tx
            lastRx = rx
        }
        lastAtMs = now
    }

    fun reset() {
        lastTx = 0
        lastRx = 0
        lastAtMs = 0
        txBps = 0
        rxBps = 0
    }

    fun snapshot(): Pair<Long, Long> = txBps to rxBps

    /// Formats `1.2 MB/s` style rates: 1024-based, one decimal for MB, none for KB
    fun format(txBps: Long, rxBps: Long): String {
        fun one(bytes: Long): String = when {
            bytes >= 1024 * 1024 -> String.format(
                java.util.Locale.US,
                "%.1f MB/s",
                bytes / (1024.0 * 1024.0),
            )
            bytes >= 1024 -> String.format(
                java.util.Locale.US,
                "%.0f KB/s",
                bytes / 1024.0,
            )
            else -> "$bytes B/s"
        }
        return "↑ ${one(txBps)}  ↓ ${one(rxBps)}"
    }
}
