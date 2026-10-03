package com.haoze.diting.crash

import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Lightweight, pure-Kotlin binary Protobuf decoder and formatter for the
 * Android 12+ (API 31+) ApplicationExitInfo.traceInputStream (tombstone.proto).
 *
 * Eliminates the mass of garbled output produced when the raw protobuf binary
 * stream is force-read as UTF-8 text, and filters out the hundreds of
 * kilobytes of useless memory-page dumps (Memory Dump), extracting only the
 * core diagnostic fields:
 * - Signal, Abort Message (e.g. FORTIFY overflow, OOM exit details)
 * - Crashing thread name, structured symbolized backtrace, key registers
 * - Device build fingerprint, architecture, process PID/TID/UID, crash timestamp
 *
 * Shrinks a single native crash report from 500KB+ to roughly 2-4KB (a 99%
 * reduction) while keeping the standard, readable tombstone layout.
 */
object TombstoneParser {

    typealias BacktraceFrame = com.haoze.diting.crash.BacktraceFrame
    typealias ThreadInfo = com.haoze.diting.crash.ThreadInfo
    typealias ParsedTombstone = com.haoze.diting.crash.ParsedTombstone

    /**
     * Parses the stream from ApplicationExitInfo.getTraceInputStream() and
     * produces a formatted report.
     */
    fun parse(stream: InputStream): String {
        val bytes = runCatching {
            val buffer = ByteArray(8192)
            val out = ByteArrayOutputStream()
            var read: Int
            // Cap at 1MB of raw binary; more than enough to cover the full
            // protobuf header and call stacks
            var total = 0
            val maxBytes = 1024 * 1024
            while (stream.read(buffer).also { read = it } != -1) {
                out.write(buffer, 0, read)
                total += read
                if (total >= maxBytes) break
            }
            out.toByteArray()
        }.getOrNull() ?: return "(Unable to read trace stream)"

        return parse(bytes)
    }

    /**
     * Parses a binary tombstone byte array.
     */
    fun parse(bytes: ByteArray): String {
        if (bytes.isEmpty()) return "(Empty tombstone trace)"

        // 1. Binary protobuf stream (introduced in Android 12)
        if (TombstoneWireReader.isLikelyProtobuf(bytes)) {
            return runCatching {
                val result = TombstoneProtobufDecoder.parse(bytes)
                if (result.signalNumber > 0 || result.signalName.isNotBlank() ||
                    result.abortMessage.isNotBlank() || result.buildFingerprint.isNotBlank() ||
                    result.threads.isNotEmpty()
                ) {
                    result.format()
                } else {
                    TombstoneTextSanitizer.fallbackExtractText(bytes)
                }
            }.getOrElse {
                TombstoneTextSanitizer.fallbackExtractText(bytes)
            }
        }

        // 2. Legacy plain-text tombstone (Android 11 or custom ROMs)
        return TombstoneTextSanitizer.sanitizePlainTextTombstone(bytes)
    }
}
