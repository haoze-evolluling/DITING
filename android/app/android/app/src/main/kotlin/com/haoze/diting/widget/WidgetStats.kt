package com.haoze.diting.widget

import android.content.Context
import com.haoze.diting.control.DataPlaneControl
import com.haoze.diting.log.LegacyDb
import java.util.Calendar

/// Today's blocked-request count for the home screen widget.
///
/// Each work mode keeps its own `dns_log` store, so the database is picked from the work mode the
/// same way the services do. A missing file, a locked database or a missing table all mean "no
/// number to show" (null) instead of a crash inside a broadcast receiver.
internal object WidgetStats {
    private const val TABLE = "dns_log"
    private const val BLOCKED_RESULT = "BLOCKED"

    fun blockedToday(context: Context): Int? {
        val databaseName = when (DataPlaneControl.workMode(context)) {
            DataPlaneControl.WORK_MODE_DNS -> "diting_server_logs"
            DataPlaneControl.WORK_MODE_EXPRESS -> "diting_express"
            else -> "diting_database"
        }
        val db = LegacyDb.writable(context, databaseName) ?: return null
        if (!LegacyDb.hasTable(db, TABLE)) return null
        return runCatching {
            db.rawQuery(
                "SELECT COUNT(*) FROM $TABLE WHERE result = ? AND timestamp >= ?",
                arrayOf(BLOCKED_RESULT, startOfDayMillis().toString()),
            ).use { cursor -> if (cursor.moveToFirst()) cursor.getInt(0) else null }
        }.getOrNull()
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
