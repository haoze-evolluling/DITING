package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.log.RequestStats
import com.haoze.diting.log.TrafficRateMonitor
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

/// The optional detail line under the status text: request counts and the speed readout, in the
/// order the user chose. Labels come from Dart (`stats_labels`) so they follow the in-app
/// language; the Chinese fallbacks only show before Dart has written them once.
object NotificationStatsLine {
    private val FALLBACK_LABELS = mapOf(
        "total" to "请求",
        "passed" to "通过",
        "filtered" to "过滤",
        "failed" to "失败",
        "cached" to "缓存命中",
        "rewritten" to "覆写",
    )

    /// Null when nothing is enabled, so the caller keeps the body to the status text alone.
    /// [withSpeed] is false where no traffic monitor runs (express and server modes).
    fun compose(context: Context, withSpeed: Boolean): String? {
        val items = NotificationSettings.statsItems(context)
        if (items.isEmpty()) return null
        val labels = labels(context)
        val stats = RequestStats.snapshot()
        val number = NumberFormat.getIntegerInstance(Locale.US)
        val parts = items.mapNotNull { id ->
            val value = when (id) {
                "total" -> stats.total
                "passed" -> stats.passed
                "filtered" -> stats.filtered
                "failed" -> stats.failed
                "cached" -> stats.cached
                "rewritten" -> stats.rewritten
                "speed" -> {
                    if (!withSpeed) return@mapNotNull null
                    val (tx, rx) = TrafficRateMonitor.snapshot()
                    return@mapNotNull TrafficRateMonitor.format(tx, rx)
                }
                else -> return@mapNotNull null
            }
            "${labels[id] ?: FALLBACK_LABELS[id] ?: id} ${number.format(value)}"
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString("  ·  ")
    }

    private fun labels(context: Context): Map<String, String> {
        val raw = NotificationSettings.statsLabelsJson(context) ?: return emptyMap()
        return runCatching {
            val obj = JSONObject(raw)
            obj.keys().asSequence().associateWith { obj.optString(it) }
                .filterValues { it.isNotBlank() }
        }.getOrDefault(emptyMap())
    }
}
