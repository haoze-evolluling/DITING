package com.haoze.diting.log

/// The batched entry points of the log kernel, kept apart from [LogNative] so that file stays a
/// flat list of JNI declarations.
///
/// These calls replace a loop of per-row JNI crossings with one payload:
///
/// * [queueSubmitMany] takes the `dns_log` rows of one engine batch and enqueues all of them under
///   a single queue lock;
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
): LogHttpBatchOutcome {
    val reader = LogPayload.Reader(
        requireNotNull(
            instance.httpEvents(stats, queue, modeTag(mode), packed, System.currentTimeMillis()),
        ) { "native HTTP event batch rejected the payload" },
    )
    return when (reader.u8()) {
        0 -> LogHttpBatchOutcome.Closed
        1 -> LogHttpBatchOutcome.Hidden
        2 -> LogHttpBatchOutcome.Enqueued(
            overflow = reader.count(),
            batchFull = reader.u8() != 0,
            flushDelayMs = reader.i64(),
        )
        else -> throw IllegalStateException("native HTTP event batch returned no status")
    }
}

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
