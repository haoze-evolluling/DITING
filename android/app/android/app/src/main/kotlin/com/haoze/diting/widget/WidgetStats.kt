package com.haoze.diting.widget

import android.content.Context
import com.haoze.diting.control.DataPlaneControl
import com.haoze.diting.log.LegacyDb
import java.util.Calendar
import java.util.Locale

/// Today's figures for the home screen widget.
///
/// Each work mode keeps its own `dns_log` store, so the database is picked from the work mode the
/// same way the services do. A missing file, a locked database or a missing table all mean "no
/// number to show" (null) instead of a crash inside a broadcast receiver.
internal object WidgetStats {
    private const val TABLE = "dns_log"
    private const val BLOCKED_RESULT = "BLOCKED"

    /// Blocked and total requests since local midnight. Both are null when the store is absent.
    data class Snapshot(val blockedToday: Int?, val totalToday: Int?)

    fun snapshot(context: Context): Snapshot {
        val databaseName = when (DataPlaneControl.workMode(context)) {
            DataPlaneControl.WORK_MODE_DNS -> "diting_server_logs"
            DataPlaneControl.WORK_MODE_EXPRESS -> "diting_express"
            else -> "diting_database"
        }
        val db = LegacyDb.writable(context, databaseName) ?: return Snapshot(null, null)
        if (!LegacyDb.hasTable(db, TABLE)) return Snapshot(null, null)
        return runCatching {
            db.rawQuery(
                "SELECT COUNT(*), COUNT(CASE WHEN result = ? THEN 1 END) FROM $TABLE " +
                    "WHERE timestamp >= ?",
                arrayOf(BLOCKED_RESULT, startOfDayMillis().toString()),
            ).use { cursor ->
                if (!cursor.moveToFirst()) return@use Snapshot(null, null)
                Snapshot(blockedToday = cursor.getInt(1), totalToday = cursor.getInt(0))
            }
        }.getOrNull() ?: Snapshot(null, null)
    }

    /// Thousands-separated count; above 100k switches to compact form, like `dashboardCount`.
    fun formatCount(value: Int): String {
        if (value >= 100_000) return "${value / 1000}k"
        val digits = value.toString()
        val builder = StringBuilder(digits.length + digits.length / 3)
        for ((index, char) in digits.withIndex()) {
            if (index > 0 && (digits.length - index) % 3 == 0) builder.append(',')
            builder.append(char)
        }
        return builder.toString()
    }

    /// One-decimal percentage, or null when there is nothing to divide by.
    fun formatRate(blocked: Int?, total: Int?): String? {
        if (blocked == null || total == null || total <= 0) return null
        val percent = blocked * 100.0 / total
        return String.format(Locale.US, "%.1f%%", percent)
    }

    private fun startOfDayMillis(): Long {
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }
}
