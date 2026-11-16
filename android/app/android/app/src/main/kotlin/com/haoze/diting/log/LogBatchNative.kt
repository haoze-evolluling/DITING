package com.haoze.diting.log

/// The batched entry points of the log kernel, kept apart from [LogNative] so that file stays a
/// flat list of JNI declarations.
///
/// These calls replace a loop of per-row JNI crossings with one payload:
///
/// * [dnsBatchSubmit] takes the engine's DNS batch and runs the counters, the classification and
///   the writer queue in one call — the rows never come back to Kotlin for a re-pack;
/// * [queueSubmitMany] enqueues an already-classified race/bootstrap batch under one queue lock;
/// * [httpEvents] takes one packed batch of MITM relay decisions, feeds the request counters,
///   classifies the rows and enqueues them — the three steps that used to be three JNI calls per
///   request (`httpEvent` plus `queueSubmit`, with Kotlin unpacking and repacking the row between
///   them);
/// * [raceRows] / [bootstrapRows] classify one engine batch of race or bootstrap inputs and answer
///   the rows the writer queue takes, so a burst costs one call instead of one pair per event.
///
/// Payload layouts are the ones documented in `rust/diting-log-core/src/api/`.

/// `u32 count | rows(u32 length | bytes)`; the answer is the same as a single submit.
internal fun LogNative.Companion.queueSubmitMany(
    handle: Long,
    rows: List<ByteArray>,
): LogQueueSubmit {
    val packed = LogPayload.pack { out ->
        out.writeInt(rows.size)
        rows.forEach { LogPayload.writeBlob(out, it) }
    }
    val reader = LogPayload.Reader(
        requireNotNull(instance.queueSubmitMany(handle, packed, System.currentTimeMillis())) {
            "native writer queue rejected the batch"
        },
    )
    return readSubmit(reader)
}

/// `u32 count | (package, authority, protocol, outcome, matched rule)` per event.
internal fun LogNative.Companion.httpEvents(
    stats: Long,
    queue: Long,
    mode: String,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.httpEvents(stats, queue, modeTag(mode), packed, System.currentTimeMillis()),
    "HTTP event batch",
)

/// One DNS batch: counters, classification and the writer queue in a single crossing.
///
/// `packed` is the engine's own batch. The kernel classifies and enqueues it itself, so neither
/// the rows nor a re-packed `queueSubmitMany` payload cross the boundary.
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

/// One engine race batch: classification and the writer queue in a single crossing.
internal fun LogNative.Companion.raceRowsSubmit(
    queue: Long,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.raceRowsSubmit(queue, packed, System.currentTimeMillis()),
    "race batch",
)

/// One engine bootstrap batch, classified and enqueued like [raceRowsSubmit].
internal fun LogNative.Companion.bootstrapRowsSubmit(
    queue: Long,
    packed: ByteArray,
): LogBatchOutcome = readBatchOutcome(
    instance.bootstrapRowsSubmit(queue, packed, System.currentTimeMillis()),
    "bootstrap batch",
)

/// `u32 count | rows(race input)`; the answer is the writer rows in the same framing.
internal fun LogNative.Companion.raceRows(packed: ByteArray): List<ByteArray> =
    readRowBatch(
        requireNotNull(instance.raceRows(packed, System.currentTimeMillis())) {
            "native race batch rejected the payload"
        },
    )

/// `u32 count | rows(bootstrap input)`; the answer is the writer rows in the same framing.
internal fun LogNative.Companion.bootstrapRows(packed: ByteArray): List<ByteArray> =
    readRowBatch(
        requireNotNull(instance.bootstrapRows(packed, System.currentTimeMillis())) {
            "native bootstrap batch rejected the payload"
        },
    )

private fun readRowBatch(payload: ByteArray): List<ByteArray> {
    val reader = LogPayload.Reader(payload)
    return List(reader.count()) { reader.blob() }
}

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
