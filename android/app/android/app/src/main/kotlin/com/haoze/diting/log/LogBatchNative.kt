package com.haoze.diting.log


internal fun LogNative.Companion.queueSubmitMany(
    handle: Long,
    rows: List<ByteArray>,
): LogQueueSubmit {
    val packed = LogPayload.pack { out -> LogPayload.writeBlobs(out, rows) }
    val reader = LogPayload.Reader(
        requireNotNull(instance.queueSubmitMany(handle, packed, System.currentTimeMillis())) {
            "native writer queue rejected the batch"
        },
    )
    return readSubmit(reader)
}

internal fun LogNative.Companion.httpEvents(
    stats: Long,
    queue: Long,
    mode: String,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.httpEvents(stats, queue, modeTag(mode), packed, System.currentTimeMillis()),
    "HTTP event batch",
)

internal fun LogNative.Companion.dnsBatchSubmit(
    stats: Long,
    queue: Long,
    mode: String,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.dnsBatchSubmit(stats, queue, modeTag(mode), packed, System.currentTimeMillis()),
    "DNS batch",
)

private fun readBatchOutcome(payload: ByteArray?, what: String): LogBatchOutcome {
    val reader = LogPayload.Reader(
        requireNotNull(payload) { "native $what rejected the payload" },
    )
    return when (reader.u8()) {
        0 -> LogBatchOutcome.Closed
        1 -> LogBatchOutcome.Hidden
        2 -> LogBatchOutcome.Enqueued(
            overflow = reader.count(),
            batchFull = reader.u8() != 0,
            flushDelayMs = reader.i64(),
        )
        else -> throw IllegalStateException("native $what returned no status")
    }
}

internal fun LogNative.Companion.raceRowsSubmit(
    queue: Long,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.raceRowsSubmit(queue, packed, System.currentTimeMillis()),
    "race batch",
)

internal fun LogNative.Companion.bootstrapRowsSubmit(
    queue: Long,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.bootstrapRowsSubmit(queue, packed, System.currentTimeMillis()),
    "bootstrap batch",
)

internal fun LogNative.Companion.raceRows(packed: ByteArray): List<ByteArray> =
    readRowBatch(
        requireNotNull(instance.raceRows(packed, System.currentTimeMillis())) {
            "native race batch rejected the payload"
        },
    )

internal fun LogNative.Companion.bootstrapRows(packed: ByteArray): List<ByteArray> =
    readRowBatch(
        requireNotNull(instance.bootstrapRows(packed, System.currentTimeMillis())) {
            "native bootstrap batch rejected the payload"
        },
    )

private fun readRowBatch(payload: ByteArray): List<ByteArray> =
    LogPayload.Reader(payload).blobs()

private fun readSubmit(reader: LogPayload.Reader): LogQueueSubmit {
    if (reader.u8() == 0) {
        return LogQueueSubmit(accepted = false, overflow = 0, batchFull = false, flushDelayMs = 0)
    }
    return LogQueueSubmit(
        accepted = true,
        overflow = reader.count(),
        batchFull = reader.u8() != 0,
        flushDelayMs = reader.i64(),
    )
}
