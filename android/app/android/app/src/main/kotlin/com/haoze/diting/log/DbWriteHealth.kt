package com.haoze.diting.log

import android.util.Log
import java.util.concurrent.atomic.AtomicLong

/// Health of the log-table writers, and the only place that logs a write failure.
///
/// 2.1.7 printed a 25-line stack trace per failed open, from every engine callback thread: the
/// 2026-10-27 export had ~7000 such lines in four minutes. That flooded logcat (the startup lines
/// were pushed out of the ring buffer, so the export had no context) and slowed the DNS hot path.
/// Failures are now counted and reported once per window, and the counters are exposed to the
/// troubleshooting page so a silent "no logs at all" becomes visible.
internal object DbWriteHealth {
    private const val TAG = "DbWriteHealth"
    private const val WARN_WINDOW_MS = 60_000L

    /// Why rows were thrown away. 2.1.9 only had one total, and "181558 dropped, no cause" could
    /// not tell a full queue from a table check that failed once and latched.
    enum class DropReason(val key: String) {
        /// The bounded queue was full because the database stayed busy for too long.
        OVERFLOW("overflow"),

        /// The table really is not in the file (wrong database, or schema not created yet).
        TABLE_MISSING("tableMissing"),

        /// No database file at all.
        NO_DATABASE("noDatabase"),

        /// The writer was closed with rows it could no longer write.
        CLOSED("closed"),
    }

    private val droppedRows = AtomicLong(0)
    private val droppedBy = DropReason.entries.associateWith { AtomicLong(0) }
    private val openFailures = AtomicLong(0)
    private val suppressed = AtomicLong(0)

    @Volatile
    private var lastWarnAt = 0L

    @Volatile
    private var lastCause: String? = null

    @Volatile
    private var lastDrop: String? = null

    /// Rows that could not be persisted at all. Called per row on overflow, so the logging path is
    /// gated by a volatile read before it takes the [warn] lock.
    fun onDropped(rows: Int, reason: DropReason, table: String) {
        if (rows <= 0) return
        droppedRows.addAndGet(rows.toLong())
        droppedBy.getValue(reason).addAndGet(rows.toLong())
        lastDrop = "$table:${reason.key}"
        if (System.currentTimeMillis() - lastWarnAt >= WARN_WINDOW_MS) {
            warn(TAG, "dropped $rows row(s) from $table (${reason.key})")
        }
    }

    fun onOpenFailure(databaseName: String, cause: Throwable?) {
        openFailures.incrementAndGet()
        warn(TAG, "unable to open $databaseName", cause)
    }

    /// One line per [WARN_WINDOW_MS]; the first failure of a window keeps its stack trace.
    @Synchronized
    fun warn(tag: String, message: String, cause: Throwable? = null) {
        if (cause != null) lastCause = "${cause.javaClass.simpleName}: ${cause.message}"
        val now = System.currentTimeMillis()
        if (now - lastWarnAt < WARN_WINDOW_MS) {
            suppressed.incrementAndGet()
            return
        }
        val more = suppressed.getAndSet(0)
        val suffix = if (more > 0) " (+$more suppressed in ${WARN_WINDOW_MS / 1000}s)" else ""
        lastWarnAt = now
        if (cause == null) Log.w(tag, message + suffix) else Log.w(tag, message + suffix, cause)
    }

    /// Payload for the diagnostics channel; zero counters and an empty cause mean "healthy".
    fun snapshot(): Map<String, Any> = mapOf(
        "droppedRows" to droppedRows.get(),
        "droppedByReason" to droppedBy.entries.associate { (reason, count) -> reason.key to count.get() },
        "lastDrop" to (lastDrop ?: ""),
        "openFailures" to openFailures.get(),
        "suppressed" to suppressed.get(),
        "lastCause" to (lastCause ?: ""),
    )
}
