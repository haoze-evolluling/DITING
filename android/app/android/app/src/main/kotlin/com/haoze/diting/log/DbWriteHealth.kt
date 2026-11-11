package com.haoze.diting.log

import android.util.Log

/// Health of the log-table writers, and the only place that logs a write failure.
///
/// 2.1.7 printed a 25-line stack trace per failed open, from every engine callback thread: the
/// 2026-10-27 export had ~7000 such lines in four minutes. That flooded logcat (the startup lines
/// were pushed out of the ring buffer, so the export had no context) and slowed the DNS hot path.
/// Failures are now counted in the log kernel and reported once per window; `Log.w` and the
/// diagnostics-channel map shape stay here.
internal object DbWriteHealth {
    private const val TAG = "DbWriteHealth"

    /// Why rows were thrown away. 2.1.9 only had one total, and "181558 dropped, no cause" could
    /// not tell a full queue from a table check that failed once and latched. The tags must match
    /// `health::DropReason::ALL` in the kernel.
    enum class DropReason(val tag: Int) {
        /// The bounded queue was full because the database stayed busy for too long.
        OVERFLOW(0),

        /// The table really is not in the file (wrong database, or schema not created yet).
        TABLE_MISSING(1),

        /// No database file at all.
        NO_DATABASE(2),

        /// The writer was closed with rows it could no longer write.
        CLOSED(3),
    }

    private val handle: Long = LogNative.healthNew()

    /// Rows that could not be persisted at all, with the reason this call is allowed to report.
    fun onDropped(rows: Int, reason: DropReason, table: String) {
        val line = LogNative.healthDropped(handle, rows, reason.tag, table) ?: return
        Log.w(TAG, line)
    }

    fun onOpenFailure(databaseName: String, cause: Throwable?) {
        val line = LogNative.healthOpenFailure(handle, databaseName, describe(cause)) ?: return
        Log.w(TAG, line)
    }

    /// One line per window; the first failure of a window keeps its stack trace.
    fun warn(tag: String, message: String, cause: Throwable? = null) {
        val line = LogNative.healthWarn(handle, message, describe(cause)) ?: return
        if (cause == null) Log.w(tag, line) else Log.w(tag, line, cause)
    }

    /// Payload for the diagnostics channel; zero counters and an empty cause mean "healthy".
    fun snapshot(): Map<String, Any> = LogNative.healthSnapshot(handle).let { health ->
        mapOf(
            "droppedRows" to health.droppedRows,
            "droppedByReason" to health.droppedByReason,
            "lastDrop" to health.lastDrop,
            "openFailures" to health.openFailures,
            "suppressed" to health.suppressed,
            "lastCause" to health.lastCause,
        )
    }

    /// The kernel stores `Class: message`, which is what the diagnostics page shows.
    private fun describe(cause: Throwable?): String =
        cause?.let { "${it.javaClass.simpleName}: ${it.message}" }.orEmpty()
}
