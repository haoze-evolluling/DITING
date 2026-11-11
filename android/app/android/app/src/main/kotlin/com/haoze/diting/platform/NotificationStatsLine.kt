package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.log.RequestStats
import com.haoze.diting.log.TrafficRateMonitor

/// The optional detail line under the status text: request counts and the speed readout, in the
/// order the user chose. Labels come from Dart (`stats_labels`) so they follow the in-app
/// language; the Chinese fallbacks and the number/speed formatting live in
/// `rust/diting-notification-core`, which only sees the ordered ids and the counters.
object NotificationStatsLine {
    /// Null when nothing is enabled, so the caller keeps the body to the status text alone.
    /// [withSpeed] is false where no traffic monitor runs (express and server modes).
    fun compose(context: Context, withSpeed: Boolean): String? {
        val items = NotificationSettings.statsItems(context)
        if (items.isEmpty()) return null
        val stats = RequestStats.snapshot()
        val (tx, rx) = if (withSpeed && "speed" in items) {
            TrafficRateMonitor.snapshot()
        } else {
            0L to 0L
        }
        return NotificationNative.compose(
            items = items,
            labelsJson = NotificationSettings.statsLabelsJson(context).orEmpty(),
            total = stats.total,
            passed = stats.passed,
            filtered = stats.filtered,
            failed = stats.failed,
            cached = stats.cached,
            rewritten = stats.rewritten,
            withSpeed = withSpeed,
            txBps = tx,
            rxBps = rx,
        )
    }
}
