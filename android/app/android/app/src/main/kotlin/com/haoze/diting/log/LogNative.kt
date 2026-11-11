package com.haoze.diting.log

/// Native log kernel, the JNI face of `rust/diting-log-core`.
///
/// The payload layouts are documented in `rust/diting-log-core/src/api.rs`; every request is one
/// packed `ByteArray` (the builders live next to the callers) and every answer is one packed
/// `ByteArray`, both big-endian. The library is required: a build that forgot
/// `python rust/build_android.py` throws an [IllegalStateException] instead of running a second
/// classifier in Kotlin.
///
/// The `Long` handles are boxed kernels (`Stats`, `Traffic`, `Health`, `Attr`, `Queue`); each one
/// is owned by exactly one Kotlin object and freed where that object used to be cleared.
internal class LogNative private constructor() {
    external fun dnsBatch(stats: Long, modeTag: Int, packed: ByteArray, nowMs: Long): ByteArray?
    external fun httpEvent(stats: Long, modeTag: Int, packed: ByteArray, nowMs: Long): ByteArray?
    external fun raceRow(packed: ByteArray, nowMs: Long): ByteArray?
    external fun bootstrapRow(packed: ByteArray, nowMs: Long): ByteArray?
    external fun retentionPlan(packed: ByteArray): ByteArray?
    external fun crashSelect(packed: ByteArray): ByteArray?

    external fun statsNew(): Long
    external fun statsFree(handle: Long)
    external fun statsRequestReset(handle: Long)
    external fun statsRateReset(handle: Long)
    external fun statsSnapshot(handle: Long): ByteArray?
    external fun rateTick(handle: Long, tx: Long, rx: Long, nowMs: Long)
    external fun rateSnapshot(handle: Long, nowMs: Long): ByteArray?

    external fun trafficNew(): Long
    external fun trafficFree(handle: Long)
    external fun trafficOnTick(handle: Long, packed: ByteArray): ByteArray?
    external fun trafficTake(handle: Long): ByteArray?
    external fun trafficRequeue(handle: Long, packed: ByteArray): Boolean
    external fun trafficBackoff(handle: Long, nowMs: Long): Long
    external fun trafficResetBackoff(handle: Long)
    external fun trafficInBackoff(handle: Long, nowMs: Long): Boolean
    external fun trafficClear(handle: Long): Int

    external fun healthNew(): Long
    external fun healthFree(handle: Long)
    external fun healthDropped(handle: Long, packed: ByteArray, nowMs: Long): ByteArray?
    external fun healthOpenFailure(
        handle: Long,
        databaseName: String,
        cause: String,
        nowMs: Long,
    ): ByteArray?

    external fun healthWarn(handle: Long, message: String, cause: String, nowMs: Long): ByteArray?
    external fun healthSnapshot(handle: Long): ByteArray?

    external fun attrNew(): Long
    external fun attrFree(handle: Long)
    external fun attrUidLookup(handle: Long, packed: ByteArray, nowMs: Long): ByteArray?
    external fun attrUidStore(handle: Long, packed: ByteArray, uid: Int, nowMs: Long): Boolean
    external fun attrPackageLookup(handle: Long, uid: Int): ByteArray?
    external fun attrPackageStore(handle: Long, uid: Int, name: String)
    external fun attrClear(handle: Long)

    external fun queueNew(settingsTag: Int): Long
    external fun queueFree(handle: Long)
    external fun queueSubmit(handle: Long, packed: ByteArray, nowMs: Long): ByteArray?
    external fun queueTake(handle: Long): ByteArray?
    external fun queueRequeue(handle: Long, packed: ByteArray): Int
    external fun queueBackoff(handle: Long, nowMs: Long): Long
    external fun queueResetBackoff(handle: Long)
    external fun queueRetryWait(handle: Long, nowMs: Long): Long
    external fun queueInBackoff(handle: Long, nowMs: Long): Boolean
    external fun queueMissingLatched(handle: Long, nowMs: Long): Boolean
    external fun queueLatchMissing(handle: Long, nowMs: Long)
    external fun queueMarkClosed(handle: Long)
    external fun queueIsClosed(handle: Long): Boolean
    external fun queueClose(handle: Long): Int
    external fun queuePendingLen(handle: Long): Int

    external fun storeIndex(packed: ByteArray): ByteArray?
    external fun storeDocument(packed: ByteArray): ByteArray?
    external fun capturePlan(pid: Int): ByteArray?
    external fun captureSessionNew(): Long
    external fun captureSessionFree(handle: Long)
    external fun captureLine(handle: Long, packed: ByteArray): ByteArray?
    external fun mirrorLayout(): ByteArray?
    external fun mirrorRows(packed: ByteArray): ByteArray?

    companion object {
        /// `LogMode` tags: the order of `row::LogMode`.
        const val MODE_TAG_ALL = 0
        const val MODE_TAG_BLOCKED_AND_ERRORS = 1
        const val MODE_TAG_OFF = 2

        /// `queue_settings` tags: `queue::LOG_TABLE` and `queue::HTTP`.
        const val QUEUE_LOG_TABLE = 0
        const val QUEUE_HTTP = 1

        private val instance: LogNative by lazy {
            try {
                System.loadLibrary("diting_kernels")
                LogNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native log kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /// The mode tag `DnsLogWriter`, `HttpRequestLogWriter` and the kernel agree on.
        fun modeTag(mode: String): Int = when (mode) {
            DnsLogWriter.MODE_ALL -> MODE_TAG_ALL
            DnsLogWriter.MODE_BLOCKED_AND_ERRORS -> MODE_TAG_BLOCKED_AND_ERRORS
            DnsLogWriter.MODE_OFF -> MODE_TAG_OFF
            else -> MODE_TAG_ALL
        }

        /// Counters are fed and rows classified; the answer is the packed `dns_log` rows.
        ///
        /// The bytes are exactly what [queueSubmit] takes, so a row the kernel classified never
        /// gets rebuilt in Kotlin: `DnsLogWriter` only unpacks them into `ContentValues`.
        fun dnsBatch(stats: Long, mode: String, packed: ByteArray): List<ByteArray> {
            val payload = requireNotNull(
                instance.dnsBatch(stats, modeTag(mode), packed, System.currentTimeMillis()),
            ) { "native DNS batch rejected the payload" }
            val reader = LogPayload.Reader(payload)
            return List(reader.count()) { reader.blob() }
        }

        /// One MITM event; null when the log mode hides it (the counters were already fed).
        fun httpEvent(stats: Long, mode: String, packed: ByteArray): ByteArray? = requireNotNull(
            instance.httpEvent(stats, modeTag(mode), packed, System.currentTimeMillis()),
        ) { "native HTTP event rejected the payload" }.takeIf { it.isNotEmpty() }

        /// One race result; null when the callback carried no query name.
        fun raceRow(packed: ByteArray): ByteArray? =
            requireNotNull(instance.raceRow(packed, System.currentTimeMillis())) {
                "native race row rejected the payload"
            }.takeIf { it.isNotEmpty() }

        /// One bootstrap probe; null when the callback carried no host.
        fun bootstrapRow(packed: ByteArray): ByteArray? =
            requireNotNull(instance.bootstrapRow(packed, System.currentTimeMillis())) {
                "native bootstrap row rejected the payload"
            }.takeIf { it.isNotEmpty() }

        /// The two retention windows and the tables one sweep visits.
        fun retentionPlan(
            logDays: Int?,
            trafficDays: Int?,
            nowMs: Long,
        ): LogRetentionPlan {
            val packed = LogPayload.pack { out ->
                out.writeByte(if (logDays == null) 0 else 1)
                out.writeInt(logDays ?: 0)
                out.writeByte(if (trafficDays == null) 0 else 1)
                out.writeInt(trafficDays ?: 0)
                out.writeLong(nowMs)
            }
            val reader = LogPayload.Reader(
                requireNotNull(instance.retentionPlan(packed)) {
                    "native retention plan rejected the payload"
                },
            )
            return LogRetentionPlan(
                logDays = reader.i32(),
                logCutoffMs = reader.i64(),
                trafficDays = reader.i32(),
                trafficCutoffMs = reader.i64(),
                tables = List(reader.count()) { reader.string() },
                trafficTable = reader.string(),
                batchRows = reader.i64(),
            )
        }

        /// This app's crash-buffer blocks, flattened back into lines.
        fun crashSelect(packageName: String, lines: List<String>): List<String> {
            val packed = LogPayload.pack { out ->
                LogPayload.writeString(out, packageName)
                out.writeInt(lines.size)
                lines.forEach { LogPayload.writeString(out, it) }
            }
            val reader = LogPayload.Reader(
                requireNotNull(instance.crashSelect(packed)) {
                    "native crash selector rejected the payload"
                },
            )
            return List(reader.count()) { reader.string() }
        }

        fun statsNew(): Long = requireHandle(instance.statsNew(), "stats")
        fun statsFree(handle: Long) = instance.statsFree(handle)
        fun statsRequestReset(handle: Long) = instance.statsRequestReset(handle)
        fun statsRateReset(handle: Long) = instance.statsRateReset(handle)
        fun rateTick(handle: Long, tx: Long, rx: Long) =
            instance.rateTick(handle, tx, rx, System.currentTimeMillis())

        fun statsSnapshot(handle: Long): LogRequestSnapshot {
            val reader = LogPayload.Reader(
                requireNotNull(instance.statsSnapshot(handle)) {
                    "native request counters returned no value"
                },
            )
            return LogRequestSnapshot(
                total = reader.i64(),
                passed = reader.i64(),
                filtered = reader.i64(),
                cached = reader.i64(),
                rewritten = reader.i64(),
                failed = reader.i64(),
            )
        }

        fun rateSnapshot(handle: Long): Pair<Long, Long> {
            val reader = LogPayload.Reader(
                requireNotNull(instance.rateSnapshot(handle, System.currentTimeMillis())) {
                    "native traffic rates returned no value"
                },
            )
            return reader.i64() to reader.i64()
        }

        fun trafficNew(): Long = requireHandle(instance.trafficNew(), "traffic")
        fun trafficFree(handle: Long) = instance.trafficFree(handle)
        fun trafficClear(handle: Long): Int = instance.trafficClear(handle)
        fun trafficBackoff(handle: Long): Long =
            instance.trafficBackoff(handle, System.currentTimeMillis())

        fun trafficResetBackoff(handle: Long) = instance.trafficResetBackoff(handle)

        fun trafficInBackoff(handle: Long): Boolean =
            instance.trafficInBackoff(handle, System.currentTimeMillis())

        fun trafficOnTick(handle: Long, packed: ByteArray): LogTrafficOutcome {
            val reader = LogPayload.Reader(
                requireNotNull(instance.trafficOnTick(handle, packed)) {
                    "native traffic tick rejected the payload"
                },
            )
            val flags = reader.u8()
            return LogTrafficOutcome(
                flush = flags and 1 != 0,
                tickTx = reader.i64(),
                tickRx = reader.i64(),
                droppedDate = reader.string().takeIf { flags and 2 != 0 && it.isNotEmpty() },
                droppedPackages = reader.count(),
            )
        }

        fun trafficTake(handle: Long): List<LogTrafficBatch> {
            val reader = LogPayload.Reader(
                requireNotNull(instance.trafficTake(handle)) {
                    "native traffic take returned no value"
                },
            )
            return List(reader.count()) {
                val date = reader.string()
                LogTrafficBatch(
                    date = date,
                    rows = List(reader.count()) {
                        LogTrafficRow(
                            packageName = reader.string(),
                            tx = reader.i64(),
                            rx = reader.i64(),
                        )
                    },
                )
            }
        }

        /// Puts a failed batch back; false means the payload did not match the take layout.
        fun trafficRequeue(handle: Long, batches: List<LogTrafficBatch>): Boolean {
            val packed = LogPayload.pack { out ->
                out.writeInt(batches.size)
                for (batch in batches) {
                    LogPayload.writeString(out, batch.date)
                    out.writeInt(batch.rows.size)
                    for (row in batch.rows) {
                        LogPayload.writeString(out, row.packageName)
                        out.writeLong(row.tx)
                        out.writeLong(row.rx)
                    }
                }
            }
            return instance.trafficRequeue(handle, packed)
        }

        fun healthNew(): Long = requireHandle(instance.healthNew(), "write health")
        fun healthFree(handle: Long) = instance.healthFree(handle)

        /// Counts the dropped rows and answers the one warning line of this window, if any.
        fun healthDropped(handle: Long, rows: Int, reasonTag: Int, table: String): String? {
            val packed = LogPayload.pack { out ->
                out.writeInt(rows)
                out.writeByte(reasonTag)
                LogPayload.writeString(out, table)
            }
            return readWarnLine(
                requireNotNull(instance.healthDropped(handle, packed, System.currentTimeMillis())) {
                    "native write health rejected the dropped-row payload"
                },
            )
        }

        fun healthOpenFailure(handle: Long, databaseName: String, cause: String): String? =
            readWarnLine(
                requireNotNull(
                    instance.healthOpenFailure(
                        handle,
                        databaseName,
                        cause,
                        System.currentTimeMillis(),
                    ),
                ) { "native write health rejected the open-failure call" },
            )

        fun healthWarn(handle: Long, message: String, cause: String): String? = readWarnLine(
            requireNotNull(
                instance.healthWarn(handle, message, cause, System.currentTimeMillis()),
            ) { "native write health rejected the warning call" },
        )

        fun healthSnapshot(handle: Long): LogHealthSnapshot {
            val reader = LogPayload.Reader(
                requireNotNull(instance.healthSnapshot(handle)) {
                    "native write health returned no value"
                },
            )
            val droppedRows = reader.i64()
            val droppedByReason = LinkedHashMap<String, Long>(4)
            repeat(4) { droppedByReason[reader.string()] = reader.i64() }
            return LogHealthSnapshot(
                droppedRows = droppedRows,
                droppedByReason = droppedByReason,
                lastDrop = reader.string(),
                openFailures = reader.i64(),
                suppressed = reader.i64(),
                lastCause = reader.string(),
            )
        }

        fun attrNew(): Long = requireHandle(instance.attrNew(), "attribution cache")
        fun attrFree(handle: Long) = instance.attrFree(handle)
        fun attrClear(handle: Long) = instance.attrClear(handle)

        /// `UidPackageCache.resolveUid`'s cache read; null means "ask the platform".
        fun attrUidLookup(handle: Long, packed: ByteArray): Int? {
            val reader = LogPayload.Reader(
                requireNotNull(
                    instance.attrUidLookup(handle, packed, System.currentTimeMillis()),
                ) { "native attribution cache rejected the flow key" },
            )
            return if (reader.u8() == 1) reader.i32() else null
        }

        fun attrUidStore(handle: Long, packed: ByteArray, uid: Int): Boolean =
            instance.attrUidStore(handle, packed, uid, System.currentTimeMillis())

        /// `PackageLookup`: null when the cache must be filled by the caller.
        fun attrPackageLookup(handle: Long, uid: Int): LogPackageLookup {
            val reader = LogPayload.Reader(
                requireNotNull(instance.attrPackageLookup(handle, uid)) {
                    "native attribution cache returned no package answer"
                },
            )
            return when (reader.u8()) {
                0 -> LogPackageLookup.Miss
                1 -> LogPackageLookup.Hit(reader.string())
                2 -> LogPackageLookup.NotKnown
                else -> throw IllegalStateException("native package lookup returned no status")
            }
        }

        fun attrPackageStore(handle: Long, uid: Int, name: String) =
            instance.attrPackageStore(handle, uid, name)

        fun queueNew(settingsTag: Int): Long =
            requireHandle(instance.queueNew(settingsTag), "writer queue")

        fun queueFree(handle: Long) = instance.queueFree(handle)

        fun queueSubmit(handle: Long, row: ByteArray): LogQueueSubmit {
            val packed = LogPayload.pack { out -> LogPayload.writeBlob(out, row) }
            val reader = LogPayload.Reader(
                requireNotNull(instance.queueSubmit(handle, packed, System.currentTimeMillis())) {
                    "native writer queue rejected the row"
                },
            )
            if (reader.u8() == 0) {
                return LogQueueSubmit(accepted = false, overflow = 0, batchFull = false, flushDelayMs = 0)
            }
            val overflow = reader.count()
            val batchFull = reader.u8() != 0
            return LogQueueSubmit(
                accepted = true,
                overflow = overflow,
                batchFull = batchFull,
                flushDelayMs = reader.i64(),
            )
        }

        /// The next transaction's rows, or null when the queue is empty.
        fun queueTake(handle: Long): List<ByteArray>? {
            val reader = LogPayload.Reader(
                requireNotNull(instance.queueTake(handle)) {
                    "native writer queue returned no batch"
                },
            )
            if (reader.u8() == 0) return null
            return List(reader.count()) { reader.blob() }
        }

        fun queueRequeue(handle: Long, rows: List<ByteArray>): Int {
            val packed = LogPayload.pack { out ->
                out.writeInt(rows.size)
                rows.forEach { LogPayload.writeBlob(out, it) }
            }
            return instance.queueRequeue(handle, packed)
        }

        fun queueBackoff(handle: Long): Long =
            instance.queueBackoff(handle, System.currentTimeMillis())

        fun queueResetBackoff(handle: Long) = instance.queueResetBackoff(handle)

        fun queueRetryWait(handle: Long): Long =
            instance.queueRetryWait(handle, System.currentTimeMillis())

        fun queueInBackoff(handle: Long): Boolean =
            instance.queueInBackoff(handle, System.currentTimeMillis())

        fun queueMissingLatched(handle: Long): Boolean =
            instance.queueMissingLatched(handle, System.currentTimeMillis())

        fun queueLatchMissing(handle: Long) =
            instance.queueLatchMissing(handle, System.currentTimeMillis())

        fun queueMarkClosed(handle: Long) = instance.queueMarkClosed(handle)
        fun queueIsClosed(handle: Long): Boolean = instance.queueIsClosed(handle)
        fun queueClose(handle: Long): Int = instance.queueClose(handle)
        fun queuePendingLen(handle: Long): Int = instance.queuePendingLen(handle)

        /// The `.log` files of one directory listing, newest first, plus how many a trim keeps.
        fun storeIndex(files: List<LogStoreFile>): LogStoreIndex {
            val packed = LogPayload.pack { out ->
                out.writeInt(files.size)
                for (file in files) {
                    LogPayload.writeString(out, file.name)
                    out.writeLong(file.lastModified)
                    out.writeLong(file.length)
                }
            }
            val reader = LogPayload.Reader(
                requireNotNull(instance.storeIndex(packed)) {
                    "native log store rejected the listing"
                },
            )
            val keep = reader.count()
            return LogStoreIndex(keep = keep, files = List(reader.count()) { readStoreFile(reader) })
        }

        private fun readStoreFile(reader: LogPayload.Reader): LogStoreFile = LogStoreFile(
            name = reader.string(),
            lastModified = reader.i64(),
            length = reader.i64(),
        )

        /// The export document; null when there is neither a file nor a crash block to show.
        fun storeDocument(
            sections: List<LogStoreSection>,
            crash: String,
            exportedAt: String,
        ): String? {
            val packed = LogPayload.pack { out ->
                out.writeInt(sections.size)
                for (section in sections) {
                    LogPayload.writeString(out, section.name)
                    LogPayload.writeOptional(out, section.content)
                }
                LogPayload.writeString(out, crash)
                LogPayload.writeString(out, exportedAt)
            }
            val reader = LogPayload.Reader(
                requireNotNull(instance.storeDocument(packed)) {
                    "native log store rejected the export payload"
                },
            )
            return if (reader.u8() == 1) reader.string() else null
        }

        /// The `logcat` attempts and the watchdog cadence for a capture of `pid`.
        fun capturePlan(pid: Int): LogCapturePlan {
            val reader = LogPayload.Reader(
                requireNotNull(instance.capturePlan(pid)) {
                    "native log capture rejected the plan request"
                },
            )
            val watchIntervalMs = reader.i64()
            return LogCapturePlan(
                watchIntervalMs = watchIntervalMs,
                attempts = List(reader.count()) {
                    List(reader.count()) { reader.string() }
                },
            )
        }

        fun captureSessionNew(): Long = requireHandle(instance.captureSessionNew(), "capture session")
        fun captureSessionFree(handle: Long) = instance.captureSessionFree(handle)

        /// Counts one captured line into the current file.
        fun captureLine(handle: Long, line: String): LogCaptureLine {
            val packed = LogPayload.pack { out -> LogPayload.writeString(out, line) }
            val reader = LogPayload.Reader(
                requireNotNull(instance.captureLine(handle, packed)) {
                    "native log capture rejected the line"
                },
            )
            return LogCaptureLine(written = reader.i64(), rotate = reader.u8() == 1)
        }

        /// How much of the engine's cache is projected, and how often.
        fun mirrorLayout(): LogMirrorLayout {
            val reader = LogPayload.Reader(
                requireNotNull(instance.mirrorLayout()) {
                    "native cache mirror returned no layout"
                },
            )
            return LogMirrorLayout(
                maxRows = reader.i64(),
                initialDelayMs = reader.i64(),
                intervalMs = reader.i64(),
            )
        }

        /// The `dns_cache` rows for one engine snapshot; the bytes are what `DnsCacheMirror` binds.
        fun mirrorRows(entries: List<LogMirrorEntry>): List<ByteArray> {
            val packed = LogPayload.pack { out ->
                out.writeInt(entries.size)
                for (entry in entries) {
                    LogPayload.writeString(out, entry.key)
                    LogPayload.writeString(out, entry.queryName)
                    out.writeInt(entry.queryType)
                    out.writeInt(entry.queryClass)
                    out.writeLong(entry.createdAt)
                    out.writeLong(entry.expiresAt)
                    out.writeLong(entry.lastHitAt)
                    out.writeLong(entry.hitCount)
                    out.writeLong(entry.originalTtlSeconds)
                    out.writeInt(entry.responseSize)
                }
            }
            val reader = LogPayload.Reader(
                requireNotNull(instance.mirrorRows(packed)) {
                    "native cache mirror rejected the snapshot"
                },
            )
            return List(reader.count()) { reader.blob() }
        }

        private fun readWarnLine(payload: ByteArray): String? {
            val reader = LogPayload.Reader(payload)
            return when (reader.u8()) {
                0 -> null
                1 -> reader.string()
                else -> throw IllegalStateException("native write health returned no status")
            }
        }

        private fun requireHandle(handle: Long, what: String): Long {
            if (handle == 0L) throw IllegalStateException("native $what handle was not created")
            return handle
        }
    }
}
