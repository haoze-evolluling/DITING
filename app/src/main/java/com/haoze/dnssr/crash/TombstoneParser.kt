package com.haoze.dnssr.crash

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.util.Locale

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

    private const val WIRE_VARINT = 0
    private const val WIRE_FIXED64 = 1
    private const val WIRE_LENGTH_DELIMITED = 2
    private const val WIRE_FIXED32 = 5

    data class BacktraceFrame(
        val pc: Long = 0L,
        val functionName: String = "",
        val functionOffset: Long = 0L,
        val fileName: String = ""
    ) {
        fun format(index: Int): String {
            val f = if (fileName.isBlank()) "<unknown>" else fileName
            val fn = if (functionName.isBlank()) "" else " ($functionName${if (functionOffset > 0) "+$functionOffset" else ""})"
            return String.format(Locale.US, "  #%02d pc %016x  %s%s", index, pc, f, fn)
        }
    }

    data class ThreadInfo(
        val tid: Int = 0,
        val name: String = "",
        val frames: MutableList<BacktraceFrame> = mutableListOf(),
        val registers: MutableMap<String, Long> = linkedMapOf()
    )

    data class ParsedTombstone(
        var arch: String = "arm64",
        var buildFingerprint: String = "",
        var revision: String = "",
        var timestamp: String = "",
        var pid: Int = 0,
        var tid: Int = 0,
        var uid: Int = 0,
        var selinuxLabel: String = "",
        var processName: String = "",
        var signalNumber: Int = 0,
        var signalName: String = "",
        var signalCode: Int = 0,
        var signalCodeName: String = "",
        var faultAddress: Long = 0L,
        var hasFaultAddress: Boolean = false,
        var abortMessage: String = "",
        val causes: MutableList<String> = mutableListOf(),
        val threads: MutableMap<Int, ThreadInfo> = linkedMapOf()
    ) {
        fun format(): String {
            val sb = StringBuilder(2048)
            sb.append("*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n")
            if (buildFingerprint.isNotBlank()) sb.append("Build fingerprint: '$buildFingerprint'\n")
            if (revision.isNotBlank()) sb.append("Revision: '$revision'\n")
            sb.append("ABI: '$arch'\n")
            if (timestamp.isNotBlank()) sb.append("Timestamp: $timestamp\n")
            sb.append(String.format(Locale.US, "Process: %s (PID: %d, TID: %d, UID: %d)\n",
                if (processName.isBlank()) "unknown" else processName, pid, tid, uid))
            if (selinuxLabel.isNotBlank()) sb.append("SELinux: $selinuxLabel\n")

            if (signalName.isNotBlank() || signalNumber > 0) {
                val codeStr = if (signalCodeName.isNotBlank()) signalCodeName else "code $signalCode"
                sb.append(String.format(Locale.US, "Signal: %d (%s), %s", signalNumber, signalName, codeStr))
                if (hasFaultAddress) {
                    sb.append(String.format(Locale.US, ", fault addr 0x%x", faultAddress))
                }
                sb.append("\n")
            }

            if (abortMessage.isNotBlank()) {
                sb.append("\nAbort Message: '$abortMessage'\n")
            }

            if (causes.isNotEmpty()) {
                for (cause in causes) {
                    sb.append("Cause: $cause\n")
                }
            }

            // Locate the crashing thread first (TID match, or the first
            // thread that has frames)
            var crashingThread = threads[tid]
            if (crashingThread == null || crashingThread.frames.isEmpty()) {
                crashingThread = threads.values.firstOrNull { it.frames.isNotEmpty() } ?: crashingThread ?: threads.values.firstOrNull()
            }

            if (crashingThread != null) {
                val threadName = if (crashingThread.name.isNotBlank()) " (${crashingThread.name})" else ""
                sb.append("\nCrashing Thread: ${if (crashingThread.tid > 0) crashingThread.tid else tid}$threadName\n")
                sb.append("Backtrace:\n")
                if (crashingThread.frames.isEmpty()) {
                    sb.append("  (No symbolic stack frames available)\n")
                } else {
                    crashingThread.frames.forEachIndexed { idx, frame ->
                        sb.append(frame.format(idx)).append("\n")
                    }
                }

                if (crashingThread.registers.isNotEmpty()) {
                    sb.append("\nRegisters:\n")
                    var count = 0
                    for ((reg, value) in crashingThread.registers) {
                        sb.append(String.format(Locale.US, "  %-4s %016x", reg, value))
                        count++
                        if (count % 4 == 0) sb.append("\n")
                    }
                    if (count % 4 != 0) sb.append("\n")
                }
            }

            // Summarize the remaining active threads (no full stacks, just key
            // info per thread, which keeps the report small)
            val otherThreads = threads.values.filter { it != crashingThread && it.frames.isNotEmpty() }
            if (otherThreads.isNotEmpty()) {
                sb.append("\nOther Active Threads (${otherThreads.size}):\n")
                for (t in otherThreads.take(8)) {
                    val topFrame = t.frames.firstOrNull()
                    val topDesc = if (topFrame != null) {
                        val fn = if (topFrame.functionName.isNotBlank()) " in ${topFrame.functionName}" else ""
                        "${topFrame.fileName}$fn"
                    } else "(idle)"
                    sb.append(String.format(Locale.US, "  Thread %d \"%s\": %s\n", t.tid, t.name, topDesc))
                }
                if (otherThreads.size > 8) {
                    sb.append(String.format(Locale.US, "  ... and %d more threads ...\n", otherThreads.size - 8))
                }
            }

            return sb.toString()
        }
    }

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
        if (isLikelyProtobuf(bytes)) {
            return runCatching {
                val result = parseProtobuf(bytes)
                if (result.signalNumber > 0 || result.signalName.isNotBlank() ||
                    result.abortMessage.isNotBlank() || result.buildFingerprint.isNotBlank() ||
                    result.threads.isNotEmpty()
                ) {
                    result.format()
                } else {
                    fallbackExtractText(bytes)
                }
            }.getOrElse {
                fallbackExtractText(bytes)
            }
        }

        // 2. Legacy plain-text tombstone (Android 11 or custom ROMs)
        return sanitizePlainTextTombstone(bytes)
    }

    private fun isLikelyProtobuf(bytes: ByteArray): Boolean {
        if (bytes.isEmpty()) return false
        val firstByte = bytes[0].toInt() and 0xFF
        // The tombstone.proto root message usually starts with field 1
        // (arch, tag=0x08) or field 2 (build_fingerprint, tag=0x12)
        if (firstByte == 0x08 || firstByte == 0x12) return true

        // Check whether the first 32 bytes contain non-printable binary
        // control characters (standard whitespace \r, \n, \t excluded)
        val checkLen = minOf(bytes.size, 32)
        for (i in 0 until checkLen) {
            val b = bytes[i].toInt() and 0xFF
            if (b == 0 || (b < 32 && b != '\n'.code && b != '\r'.code && b != '\t'.code)) {
                return true
            }
        }
        return false
    }

    private fun sanitizePlainTextTombstone(bytes: ByteArray): String {
        val text = String(bytes, StandardCharsets.UTF_8)
        val lines = text.lineSequence().take(200).toList()
        val sb = StringBuilder(text.length.coerceAtMost(8192))
        for (line in lines) {
            // Drop the huge, useless "memory map:" / "memory near " blocks so
            // the output does not balloon
            if (line.startsWith("memory map:") || line.startsWith("memory near ")) {
                sb.append("\n...(Excessive memory dumps truncated)...\n")
                break
            }
            sb.append(line).append("\n")
        }
        return sb.toString()
    }

    private fun parseProtobuf(bytes: ByteArray): ParsedTombstone {
        val result = ParsedTombstone()
        var pos = 0

        while (pos < bytes.size) {
            val tagAndWire = readVarint(bytes, pos) ?: break
            pos = tagAndWire.nextOffset
            val field = tagAndWire.value.ushr(3).toInt()
            val wire = (tagAndWire.value and 7).toInt()

            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                    when (field) {
                        1 -> result.arch = when (v.value.toInt()) {
                            0 -> "arm"
                            1 -> "arm64"
                            2 -> "x86"
                            3 -> "x86_64"
                            4 -> "riscv64"
                            else -> "arch_${v.value}"
                        }
                        5 -> result.pid = v.value.toInt()
                        6 -> result.tid = v.value.toInt()
                        7 -> result.uid = v.value.toInt()
                    }
                }
                WIRE_FIXED64 -> {
                    pos += 8
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVarint = readVarint(bytes, pos) ?: break
                    pos = lenVarint.nextOffset
                    val len = lenVarint.value.toInt()
                    if (len < 0 || pos + len > bytes.size) break

                    when (field) {
                        2 -> result.buildFingerprint = String(bytes, pos, len, StandardCharsets.UTF_8)
                        3 -> result.revision = String(bytes, pos, len, StandardCharsets.UTF_8)
                        4 -> result.timestamp = String(bytes, pos, len, StandardCharsets.UTF_8)
                        8 -> result.selinuxLabel = String(bytes, pos, len, StandardCharsets.UTF_8)
                        9 -> if (result.processName.isBlank()) {
                            result.processName = String(bytes, pos, len, StandardCharsets.UTF_8)
                        }
                        10 -> parseSignalInfo(bytes, pos, len, result)
                        11 -> result.abortMessage = String(bytes, pos, len, StandardCharsets.UTF_8)
                        12 -> parseCause(bytes, pos, len, result)
                        15 -> parseThreadEntry(bytes, pos, len, result)
                        // Skip fields 16 (memory_dump), 17 (logcat), and 18
                        // (open_fds) outright — they carry hundreds of KB of junk
                        else -> { /* skip */ }
                    }
                    pos += len
                }
                WIRE_FIXED32 -> {
                    pos += 4
                }
                else -> {
                    // Unknown wire type: bail out safely
                    break
                }
            }
        }

        return result
    }

    private fun parseSignalInfo(bytes: ByteArray, offset: Int, length: Int, target: ParsedTombstone) {
        var pos = offset
        val end = offset + length
        while (pos < end) {
            val tag = readVarint(bytes, pos) ?: break
            pos = tag.nextOffset
            val field = tag.value.ushr(3).toInt()
            val wire = (tag.value and 7).toInt()
            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                    when (field) {
                        1 -> target.signalNumber = v.value.toInt()
                        3 -> target.signalCode = v.value.toInt()
                        5 -> target.hasFaultAddress = v.value != 0L
                        6 -> target.faultAddress = v.value
                    }
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVar = readVarint(bytes, pos) ?: break
                    pos = lenVar.nextOffset
                    val len = lenVar.value.toInt()
                    if (len in 0..(end - pos)) {
                        val s = String(bytes, pos, len, StandardCharsets.UTF_8)
                        when (field) {
                            2 -> target.signalName = s
                            4 -> target.signalCodeName = s
                        }
                    }
                    pos += len
                }
                WIRE_FIXED32 -> pos += 4
                WIRE_FIXED64 -> pos += 8
                else -> break
            }
        }
    }

    private fun parseCause(bytes: ByteArray, offset: Int, length: Int, target: ParsedTombstone) {
        var pos = offset
        val end = offset + length
        while (pos < end) {
            val tag = readVarint(bytes, pos) ?: break
            pos = tag.nextOffset
            val field = tag.value.ushr(3).toInt()
            val wire = (tag.value and 7).toInt()
            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVar = readVarint(bytes, pos) ?: break
                    pos = lenVar.nextOffset
                    val len = lenVar.value.toInt()
                    if (field == 1 && len in 0..(end - pos)) {
                        val causeText = String(bytes, pos, len, StandardCharsets.UTF_8).trim()
                        if (causeText.isNotBlank()) {
                            target.causes.add(causeText)
                        }
                    }
                    pos += len
                }
                WIRE_FIXED32 -> pos += 4
                WIRE_FIXED64 -> pos += 8
                else -> break
            }
        }
    }

    private fun parseThreadEntry(bytes: ByteArray, offset: Int, length: Int, target: ParsedTombstone) {
        // Support both protobuf layouts: map<uint32, Thread> (field 1 = tid,
        // field 2 = Thread) and repeated Thread
        var pos = offset
        val end = offset + length
        var threadKey = 0
        var threadInfo: ThreadInfo? = null
        var isDirectThread = false

        while (pos < end) {
            val tag = readVarint(bytes, pos) ?: break
            pos = tag.nextOffset
            val field = tag.value.ushr(3).toInt()
            val wire = (tag.value and 7).toInt()
            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                    if (field == 1) threadKey = v.value.toInt()
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVar = readVarint(bytes, pos) ?: break
                    pos = lenVar.nextOffset
                    val len = lenVar.value.toInt()
                    // If this message directly contains field 4
                    // (BacktraceFrame) or field 3 (Register) at the top level,
                    // the entry itself is a Thread
                    if (field == 3 || field == 4) {
                        isDirectThread = true
                    }
                    if (field == 2 && len in 0..(end - pos)) {
                        threadInfo = parseThread(bytes, pos, len, threadKey)
                    }
                    pos += len
                }
                WIRE_FIXED32 -> pos += 4
                WIRE_FIXED64 -> pos += 8
                else -> break
            }
        }

        if (isDirectThread) {
            val direct = parseThread(bytes, offset, length, threadKey)
            val tid = if (direct.tid > 0) direct.tid else threadKey
            target.threads[tid] = direct
        } else if (threadInfo != null) {
            val tid = if (threadInfo.tid > 0) threadInfo.tid else threadKey
            target.threads[tid] = threadInfo
        }
    }

    private fun parseThread(bytes: ByteArray, offset: Int, length: Int, defaultTid: Int): ThreadInfo {
        var pos = offset
        val end = offset + length
        var tid = defaultTid
        var name = ""
        val frames = mutableListOf<BacktraceFrame>()
        val registers = linkedMapOf<String, Long>()

        while (pos < end) {
            val tag = readVarint(bytes, pos) ?: break
            pos = tag.nextOffset
            val field = tag.value.ushr(3).toInt()
            val wire = (tag.value and 7).toInt()
            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                    if (field == 1) tid = v.value.toInt()
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVar = readVarint(bytes, pos) ?: break
                    pos = lenVar.nextOffset
                    val len = lenVar.value.toInt()
                    if (len in 0..(end - pos)) {
                        when (field) {
                            2 -> name = String(bytes, pos, len, StandardCharsets.UTF_8)
                            3 -> parseRegister(bytes, pos, len, registers)
                            4 -> parseFrame(bytes, pos, len)?.let { frames.add(it) }
                        }
                    }
                    pos += len
                }
                WIRE_FIXED32 -> pos += 4
                WIRE_FIXED64 -> pos += 8
                else -> break
            }
        }

        return ThreadInfo(tid = tid, name = name, frames = frames, registers = registers)
    }

    private fun parseRegister(bytes: ByteArray, offset: Int, length: Int, registers: MutableMap<String, Long>) {
        var pos = offset
        val end = offset + length
        var regName = ""
        var regVal = 0L

        while (pos < end) {
            val tag = readVarint(bytes, pos) ?: break
            pos = tag.nextOffset
            val field = tag.value.ushr(3).toInt()
            val wire = (tag.value and 7).toInt()
            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                    if (field == 2) regVal = v.value
                }
                WIRE_FIXED64 -> {
                    if (pos + 8 <= end) {
                        regVal = readFixed64(bytes, pos)
                        pos += 8
                    }
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVar = readVarint(bytes, pos) ?: break
                    pos = lenVar.nextOffset
                    val len = lenVar.value.toInt()
                    if (field == 1 && len in 0..(end - pos)) {
                        regName = String(bytes, pos, len, StandardCharsets.UTF_8)
                    }
                    pos += len
                }
                WIRE_FIXED32 -> pos += 4
                else -> break
            }
        }

        if (regName.isNotBlank()) {
            registers[regName] = regVal
        }
    }

    private fun parseFrame(bytes: ByteArray, offset: Int, length: Int): BacktraceFrame? {
        var pos = offset
        val end = offset + length
        var pc = 0L
        var functionName = ""
        var functionOffset = 0L
        var fileName = ""

        while (pos < end) {
            val tag = readVarint(bytes, pos) ?: break
            pos = tag.nextOffset
            val field = tag.value.ushr(3).toInt()
            val wire = (tag.value and 7).toInt()
            when (wire) {
                WIRE_VARINT -> {
                    val v = readVarint(bytes, pos) ?: break
                    pos = v.nextOffset
                    when (field) {
                        2 -> pc = v.value
                        5 -> functionOffset = v.value
                    }
                }
                WIRE_FIXED64 -> {
                    if (pos + 8 <= end) {
                        if (field == 2) pc = readFixed64(bytes, pos)
                        pos += 8
                    }
                }
                WIRE_LENGTH_DELIMITED -> {
                    val lenVar = readVarint(bytes, pos) ?: break
                    pos = lenVar.nextOffset
                    val len = lenVar.value.toInt()
                    if (len in 0..(end - pos)) {
                        val s = String(bytes, pos, len, StandardCharsets.UTF_8)
                        when (field) {
                            4 -> functionName = s
                            6 -> fileName = s
                        }
                    }
                    pos += len
                }
                WIRE_FIXED32 -> pos += 4
                else -> break
            }
        }

        return if (pc != 0L || fileName.isNotBlank()) {
            BacktraceFrame(pc = pc, functionName = functionName, functionOffset = functionOffset, fileName = fileName)
        } else {
            null
        }
    }

    private fun fallbackExtractText(bytes: ByteArray): String {
        val sb = StringBuilder()
        sb.append("*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n")
        sb.append("(Binary Protobuf Tombstone - Parsed with Text Recovery)\n\n")

        // Extract every meaningful run of ASCII/UTF-8 text in the buffer
        var i = 0
        while (i < bytes.size) {
            val start = i
            while (i < bytes.size && (bytes[i] in 32..126 || bytes[i] == '\n'.code.toByte())) {
                i++
            }
            val len = i - start
            if (len >= 6) {
                val s = String(bytes, start, len, StandardCharsets.UTF_8).trim()
                if (s.isNotBlank() && !s.contains("????")) {
                    if (s.contains("Build fingerprint") || s.contains("SIGABRT") || s.contains("SIGSEGV") ||
                        s.contains("FORTIFY") || s.contains("prevented") || s.contains("Exception") ||
                        s.contains("OutOfMemory") || s.contains(".so") || s.contains("#0") || s.startsWith(">>>")
                    ) {
                        sb.append(s).append("\n")
                    }
                }
            }
            i++
        }
        return sb.toString()
    }

    private data class VarintResult(val value: Long, val nextOffset: Int)

    private fun readVarint(bytes: ByteArray, offset: Int): VarintResult? {
        var pos = offset
        var result = 0L
        var shift = 0
        while (pos < bytes.size && shift < 64) {
            val b = bytes[pos++].toInt() and 0xFF
            result = result or ((b and 0x7F).toLong() shl shift)
            if ((b and 0x80) == 0) {
                return VarintResult(result, pos)
            }
            shift += 7
        }
        return null
    }

    private fun readFixed64(bytes: ByteArray, offset: Int): Long {
        return (bytes[offset].toLong() and 0xFF) or
                ((bytes[offset + 1].toLong() and 0xFF) shl 8) or
                ((bytes[offset + 2].toLong() and 0xFF) shl 16) or
                ((bytes[offset + 3].toLong() and 0xFF) shl 24) or
                ((bytes[offset + 4].toLong() and 0xFF) shl 32) or
                ((bytes[offset + 5].toLong() and 0xFF) shl 40) or
                ((bytes[offset + 6].toLong() and 0xFF) shl 48) or
                ((bytes[offset + 7].toLong() and 0xFF) shl 56)
    }
}
