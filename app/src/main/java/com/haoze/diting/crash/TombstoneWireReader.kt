package com.haoze.diting.crash

/**
 * Low-level binary Protobuf wire protocol decoder and detection utilities.
 */
internal object TombstoneWireReader {
    const val WIRE_VARINT = 0
    const val WIRE_FIXED64 = 1
    const val WIRE_LENGTH_DELIMITED = 2
    const val WIRE_FIXED32 = 5

    data class VarintResult(val value: Long, val nextOffset: Int)

    fun readVarint(bytes: ByteArray, offset: Int): VarintResult? {
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

    fun readFixed64(bytes: ByteArray, offset: Int): Long {
        return (bytes[offset].toLong() and 0xFF) or
                ((bytes[offset + 1].toLong() and 0xFF) shl 8) or
                ((bytes[offset + 2].toLong() and 0xFF) shl 16) or
                ((bytes[offset + 3].toLong() and 0xFF) shl 24) or
                ((bytes[offset + 4].toLong() and 0xFF) shl 32) or
                ((bytes[offset + 5].toLong() and 0xFF) shl 40) or
                ((bytes[offset + 6].toLong() and 0xFF) shl 48) or
                ((bytes[offset + 7].toLong() and 0xFF) shl 56)
    }

    fun isLikelyProtobuf(bytes: ByteArray): Boolean {
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
}
