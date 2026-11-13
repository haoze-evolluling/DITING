package com.haoze.diting.log

/// The decoded answer types of the log kernel's payloads.
///
/// Kept apart from [LogNative] so that file stays the JNI surface alone: every type here is a
/// straight read of one payload layout in `rust/diting-log-core/src/api/`.
/// The retention sweep's plan.
internal data class LogRetentionPlan(
    val logDays: Int,
    val logCutoffMs: Long,
    val trafficDays: Int,
    val trafficCutoffMs: Long,
    val tables: List<String>,
    val trafficTable: String,
    val batchRows: Long,
)

/// `RequestStats.Snapshot`.
internal data class LogRequestSnapshot(
    val total: Long,
    val passed: Long,
    val filtered: Long,
    val cached: Long,
    val rewritten: Long,
    val failed: Long,
)

/// What one traffic tick decided.
internal data class LogTrafficOutcome(
    val flush: Boolean,
    val tickTx: Long,
    val tickRx: Long,
    val droppedDate: String?,
    val droppedPackages: Int,
)

/// One buffered `app_traffic_daily` delta.
internal data class LogTrafficRow(val packageName: String, val tx: Long, val rx: Long)

/// The buffered deltas of one date.
internal data class LogTrafficBatch(val date: String, val rows: List<LogTrafficRow>)

/// `DbWriteHealth.snapshot()`.
internal data class LogHealthSnapshot(
    val droppedRows: Long,
    val droppedByReason: Map<String, Long>,
    val lastDrop: String,
    val openFailures: Long,
    val suppressed: Long,
    val lastCause: String,
)

/// `UidPackageCache.packageForUid`'s cache answer.
internal sealed interface LogPackageLookup {
    data class Hit(val packageName: String) : LogPackageLookup
    data object Miss : LogPackageLookup
    data object NotKnown : LogPackageLookup
}

/// What one `submit` into a writer queue decided.
internal data class LogQueueSubmit(
    val accepted: Boolean,
    val overflow: Int,
    val batchFull: Boolean,
    val flushDelayMs: Long,
)

/// One directory entry of the capture folder.
internal data class LogStoreFile(val name: String, val lastModified: Long, val length: Long)

/// The capture folder after filtering and sorting; `files[0..keep]` survive a trim.
internal data class LogStoreIndex(val keep: Int, val files: List<LogStoreFile>)

/// One capture file going into an export; `content` is null when it could not be read.
internal data class LogStoreSection(val name: String, val content: String?)

/// The `logcat` attempts, in order, and how often to check whether the process is gone.
internal data class LogCapturePlan(val watchIntervalMs: Long, val attempts: List<List<String>>)

/// What one captured line did to the current file's budget.
internal data class LogCaptureLine(val written: Long, val rotate: Boolean)

/// One structured runtime event after the kernel's level/dedup gate: `wrote` is false when it was
/// filtered or swallowed as a repeat, and `line` is then empty.
internal data class LogRuntimeEventLine(val wrote: Boolean, val line: String)

/// The projection's caps and cadence.
internal data class LogMirrorLayout(val maxRows: Long, val initialDelayMs: Long, val intervalMs: Long)

/// One engine cache entry, as `Engine.getDNSCacheEntries` reported it.
internal data class LogMirrorEntry(
    val key: String,
    val queryName: String,
    val queryType: Int,
    val queryClass: Int,
    val createdAt: Long,
    val expiresAt: Long,
    val lastHitAt: Long,
    val hitCount: Long,
    val originalTtlSeconds: Long,
    val responseSize: Int,
)
