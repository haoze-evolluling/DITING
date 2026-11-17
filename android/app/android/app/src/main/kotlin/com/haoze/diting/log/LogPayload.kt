package com.haoze.diting.log

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer

/// Payload primitives for the log kernel, the Kotlin half of `rust/diting-log-core/src/payload.rs`.
///
/// Every call packs one `ByteArray` and answers one `ByteArray`, big-endian. Strings are a `u32`
/// byte length plus UTF-8; optional columns are a presence byte plus the value, so a `NULL` in the
/// database stays distinguishable from an empty string.
internal object LogPayload {
    /// Packs a payload with the writer the callbacks share.
    fun pack(write: (DataOutputStream) -> Unit): ByteArray {
        val buffer = ByteArrayOutputStream(256)
        val out = DataOutputStream(buffer)
        write(out)
        out.flush()
        return buffer.toByteArray()
    }

    fun writeString(out: DataOutputStream, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        out.writeInt(bytes.size)
        out.write(bytes)
    }

    fun writeBlob(out: DataOutputStream, value: ByteArray) {
        out.writeInt(value.size)
        out.write(value)
    }

    /// `u32 count | blobs`, the framing of the writer queue's batch payloads.
    fun writeBlobs(out: DataOutputStream, rows: List<ByteArray>) {
        out.writeInt(rows.size)
        rows.forEach { writeBlob(out, it) }
    }

    /// Presence byte plus value; null becomes a clear byte with no payload.
    fun writeOptional(out: DataOutputStream, value: String?) {
        if (value == null) {
            out.writeByte(0)
        } else {
            out.writeByte(1)
            writeString(out, value)
        }
    }

    fun writeOptionalLong(out: DataOutputStream, value: Long?) {
        if (value == null) {
            out.writeByte(0)
        } else {
            out.writeByte(1)
            out.writeLong(value)
        }
    }

    /// Big-endian reader; a short read throws like the kernel's `None` does, and the entry point
    /// turns that into an [IllegalStateException].
    class Reader(private val payload: ByteArray) {
        private val buffer: ByteBuffer = ByteBuffer.wrap(payload)

        fun u8(): Int = buffer.get().toInt() and 0xFF

        fun i32(): Int = buffer.int

        fun u32(): Long = buffer.int.toLong() and 0xFFFFFFFFL

        fun i64(): Long = buffer.long

        fun count(): Int = u32().toInt()

        /// Decodes straight out of the payload: copying the range into a fresh `ByteArray` first
        /// doubled the allocation of every string in a DNS batch.
        fun string(): String {
            val length = count()
            val start = buffer.position()
            val text = String(payload, start, length, Charsets.UTF_8)
            buffer.position(start + length)
            return text
        }

        fun blob(): ByteArray {
            val length = count()
            val start = buffer.position()
            val bytes = payload.copyOfRange(start, start + length)
            buffer.position(start + length)
            return bytes
        }

        /// A `u32 count` followed by that many blobs.
        fun blobs(): List<ByteArray> = List(count()) { blob() }

        fun optionalString(): String? = when (u8()) {
            0 -> null
            1 -> string()
            else -> throw IllegalStateException("log payload carried an unknown presence byte")
        }

        fun optionalLong(): Long? = when (u8()) {
            0 -> null
            1 -> i64()
            else -> throw IllegalStateException("log payload carried an unknown presence byte")
        }
    }
}
