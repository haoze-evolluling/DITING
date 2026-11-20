package com.haoze.diting.log

import android.util.Log

internal object DbWriteHealth {
    private const val TAG = "DbWriteHealth"

    enum class DropReason(val tag: Int) {
        OVERFLOW(0),

        TABLE_MISSING(1),

        NO_DATABASE(2),

        CLOSED(3),
    }

    private val handle: Long = LogNative.healthNew()

    fun onDropped(rows: Int, reason: DropReason, table: String) {
        val line = LogNative.healthDropped(handle, rows, reason.tag, table) ?: return
        Log.w(TAG, line)
    }

    fun onOpenFailure(databaseName: String, cause: Throwable?) {
        val line = LogNative.healthOpenFailure(handle, databaseName, describe(cause)) ?: return
        Log.w(TAG, line)
    }

    fun warn(tag: String, message: String, cause: Throwable? = null) {
        val line = LogNative.healthWarn(handle, message, describe(cause)) ?: return
        if (cause == null) Log.w(tag, line) else Log.w(tag, line, cause)
    }

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

    private fun describe(cause: Throwable?): String =
        cause?.let { "${it.javaClass.simpleName}: ${it.message}" }.orEmpty()
}
