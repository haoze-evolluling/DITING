package com.haoze.diting.crash

import com.haoze.diting.crash.TombstoneWireReader.WIRE_FIXED32
import com.haoze.diting.crash.TombstoneWireReader.WIRE_FIXED64
import com.haoze.diting.crash.TombstoneWireReader.WIRE_LENGTH_DELIMITED
import com.haoze.diting.crash.TombstoneWireReader.WIRE_VARINT
import com.haoze.diting.crash.TombstoneWireReader.readFixed64
import com.haoze.diting.crash.TombstoneWireReader.readVarint
import java.nio.charset.StandardCharsets

/**
 * Pure-Kotlin binary Protobuf decoder for Android 12+ (API 31+) tombstone.proto payloads.
 */
internal object TombstoneProtobufDecoder {

    fun parse(bytes: ByteArray): ParsedTombstone {
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
}
