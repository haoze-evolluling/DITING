package com.haoze.diting.core.dns

import com.haoze.diting.core.rule.RewriteAnswer
import com.haoze.diting.data.entity.RewriteTargetType
import java.net.InetAddress

/**
 * Builds synthetic DNS answers from hosts / rewrite rules. Kept separate from
 * DnsMessageUtils so both files stay within the project's per-file size limit.
 */
internal object DnsRewriteMessage {

    private const val HEADER_LEN = 12
    private const val TYPE_A = 1
    private const val TYPE_CNAME = 5
    private const val TYPE_AAAA = 28
    private const val CLASS_IN = 1
    private const val RCODE_NOERROR = 0
    private const val REWRITE_RESPONSE_TTL_SECONDS = 300L
    private const val RESOURCE_RECORD_HEADER_SIZE = 12
    private const val DNS_FLAG_QR = 0x80

    /**
     * Builds a synthetic answer from hosts / rewrite rules for the question.
     * An A or AAAA query is answered with a matching IP target; a CNAME query
     * is answered with a CNAME target. Returns null when no target fits the
     * question, so the caller falls through to upstream resolution.
     */
    fun buildResponse(query: ByteArray, answers: Collection<RewriteAnswer>): ByteArray? {
        if (answers.isEmpty()) return null
        val question = DnsMessageUtils.extractQuestion(query) ?: return null
        if (question.qclass != CLASS_IN) return null
        val questionEnd = questionEnd(query) ?: return null

        val rtype: Int
        val rdata: ByteArray = when (question.type) {
            TYPE_A -> {
                val ip = answers.firstOrNull { it.targetType == RewriteTargetType.IPV4 }?.targetValue
                    ?: return null
                rtype = TYPE_A
                parseIpv4(ip) ?: return null
            }
            TYPE_AAAA -> {
                val ip = answers.firstOrNull { it.targetType == RewriteTargetType.IPV6 }?.targetValue
                    ?: return null
                rtype = TYPE_AAAA
                parseIpv6(ip) ?: return null
            }
            TYPE_CNAME -> {
                val target = answers.firstOrNull { it.targetType == RewriteTargetType.CNAME }?.targetValue
                    ?: return null
                rtype = TYPE_CNAME
                encodeDomainName(target) ?: return null
            }
            else -> return null
        }

        val response = ByteArray(questionEnd + RESOURCE_RECORD_HEADER_SIZE + rdata.size)
        query.copyInto(response, 0, 0, questionEnd)
        writeResponseHeader(response, query, RCODE_NOERROR)
        writeShort(response, 4, 1)
        writeShort(response, 6, 1)
        writeShort(response, 8, 0)
        writeShort(response, 10, 0)
        var offset = questionEnd
        writeNamePointer(response, offset)
        offset += 2
        writeShort(response, offset, rtype)
        writeShort(response, offset + 2, CLASS_IN)
        writeInt(response, offset + 4, REWRITE_RESPONSE_TTL_SECONDS)
        writeShort(response, offset + 8, rdata.size)
        rdata.copyInto(response, offset + 10)
        return response
    }

    private fun parseIpv4(value: String): ByteArray? {
        val parts = value.trim().split(".")
        if (parts.size != 4) return null
        val bytes = ByteArray(4)
        parts.forEachIndexed { index, part ->
            val number = part.toIntOrNull() ?: return null
            if (number !in 0..255) return null
            bytes[index] = number.toByte()
        }
        return bytes
    }

    private fun parseIpv6(value: String): ByteArray? {
        if (!value.contains(':')) return null
        val address = runCatching { InetAddress.getByName(value.trim()).address }.getOrNull()
        return address?.takeIf { it.size == 16 }
    }

    private fun encodeDomainName(name: String): ByteArray? {
        val trimmed = name.trim().trimEnd('.')
        if (trimmed.isEmpty()) return null
        val labels = trimmed.split('.')
        if (labels.any { it.isEmpty() || it.length > 63 }) return null
        val out = ByteArray(labels.sumOf { it.length } + labels.size + 1)
        var offset = 0
        labels.forEach { label ->
            val bytes = label.toByteArray(Charsets.US_ASCII)
            out[offset] = bytes.size.toByte()
            bytes.copyInto(out, offset + 1)
            offset += bytes.size + 1
        }
        out[offset] = 0
        return out
    }

    private fun questionEnd(query: ByteArray): Int? {
        if (query.size < HEADER_LEN || readShort(query, 4) != 1) return null
        val nameEnd = skipName(query, HEADER_LEN)
        if (nameEnd < 0 || nameEnd + 4 > query.size) return null
        return nameEnd + 4
    }

    private fun skipName(buf: ByteArray, start: Int): Int {
        // Identical walk to DnsMessageUtils: handles compression pointers.
        var offset = start
        var jumped = false
        var maxJumps = 128
        var current = start

        while (maxJumps-- > 0) {
            if (offset >= buf.size) return -1
            val len = buf[offset].toInt() and 0xFF
            if (len == 0) {
                offset++
                break
            }
            if (len >= 192) {
                // Compression pointer, 2 bytes total
                if (offset + 1 >= buf.size) return -1
                if (!jumped) current = offset + 2
                offset = ((len and 0x3F) shl 8) or (buf[offset + 1].toInt() and 0xFF)
                jumped = true
                continue
            }
            offset += 1 + len
            if (offset > buf.size) return -1
        }

        return if (jumped) current else offset
    }

    private fun readShort(buf: ByteArray, offset: Int): Int =
        ((buf[offset].toInt() and 0xFF) shl 8) or (buf[offset + 1].toInt() and 0xFF)

    private fun writeShort(buf: ByteArray, offset: Int, value: Int) {
        buf[offset] = ((value ushr 8) and 0xFF).toByte()
        buf[offset + 1] = (value and 0xFF).toByte()
    }

    private fun writeInt(buf: ByteArray, offset: Int, value: Long) {
        buf[offset] = ((value ushr 24) and 0xFF).toByte()
        buf[offset + 1] = ((value ushr 16) and 0xFF).toByte()
        buf[offset + 2] = ((value ushr 8) and 0xFF).toByte()
        buf[offset + 3] = (value and 0xFF).toByte()
    }

    private fun writeNamePointer(response: ByteArray, offset: Int) {
        response[offset] = 0xC0.toByte()
        response[offset + 1] = HEADER_LEN.toByte()
    }

    private fun writeResponseHeader(response: ByteArray, query: ByteArray, responseCode: Int) {
        val requestFlagsHigh = query.getOrNull(2)?.toInt()?.and(0xFF) ?: 0
        val requestFlagsLow = query.getOrNull(3)?.toInt()?.and(0xFF) ?: 0
        response[2] = (DNS_FLAG_QR or (requestFlagsHigh and 0x79)).toByte()
        response[3] = (0x80 or (requestFlagsLow and 0x10) or (responseCode and 0x0F)).toByte()
    }
}
