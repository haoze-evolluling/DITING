package com.haoze.diting.log

internal data class LogRetentionPlan(
    val logDays: Int,
    val logCutoffMs: Long,
    val trafficDays: Int,
    val trafficCutoffMs: Long,
    val tables: List<String>,
    val trafficTable: String,
    val batchRows: Long,
)

internal data class LogRequestSnapshot(
    val total: Long,
    val passed: Long,
    val filtered: Long,
    val cached: Long,
    val rewritten: Long,
    val failed: Long,
)

internal data class LogTrafficOutcome(
    val flush: Boolean,
    val tickTx: Long,
    val tickRx: Long,
    val droppedDate: String?,
    val droppedPackages: Int,
)

internal data class LogTrafficRow(val packageName: String, val tx: Long, val rx: Long)

internal data class LogTrafficBatch(val date: String, val rows: List<LogTrafficRow>)

internal data class LogHealthSnapshot(
    val droppedRows: Long,
    val droppedByReason: Map<String, Long>,
    val lastDrop: String,
    val openFailures: Long,
    val suppressed: Long,
    val lastCause: String,
)

internal sealed interface LogPackageLookup {
    data class Hit(val packageName: String) : LogPackageLookup
    data object Miss : LogPackageLookup
    data object NotKnown : LogPackageLookup
}

internal data class LogQueueSubmit(
    val accepted: Boolean,
    val overflow: Int,
    val batchFull: Boolean,
    val flushDelayMs: Long,
)

internal sealed interface LogBatchOutcome {
    data object Closed : LogBatchOutcome

    data object Hidden : LogBatchOutcome

    data class Enqueued(
        val overflow: Int,
        val batchFull: Boolean,
        val flushDelayMs: Long,
    ) : LogBatchOutcome
}

internal data class LogStoreFile(val name: String, val lastModified: Long, val length: Long)

internal data class LogStoreIndex(val keep: Int, val files: List<LogStoreFile>)

internal data class LogStoreSection(val name: String, val content: String?)

internal data class LogCapturePlan(val watchIntervalMs: Long, val attempts: List<List<String>>)

internal data class LogCaptureLine(val written: Long, val rotate: Boolean)

internal data class LogRuntimeEventLine(val wrote: Boolean, val line: String)

internal data class LogMirrorLayout(val maxRows: Long, val initialDelayMs: Long, val intervalMs: Long)
