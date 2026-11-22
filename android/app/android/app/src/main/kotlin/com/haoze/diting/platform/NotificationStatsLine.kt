package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.log.RequestStats
import com.haoze.diting.log.TrafficRateMonitor

object NotificationStatsLine {
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
