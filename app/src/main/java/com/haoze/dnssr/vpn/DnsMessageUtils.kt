package com.haoze.dnssr.vpn

import java.net.InetAddress

/**
 * Simplified DNS message utilities.
 *
 * Parses QNAME/QTYPE from queries and builds local DNS responses; no full RR
 * parsing.
 */
object DnsMessageUtils {

    private const val HEADER_LEN = 12
    const val TYPE_A = 1
    const val TYPE_AAAA = 28
    private const val TYPE_SOA = 6
    private const val TYPE_OPT = 41
    private const val CLASS_IN = 1
    private const val BLOCK_RESPONSE_TTL_SECONDS = 300L
    private const val RESOURCE_RECORD_HEADER_SIZE = 12
    private const val SOA_RDATA_SIZE = 22
    private const val SOA_RECORD_SIZE = RESOURCE_RECORD_HEADER_SIZE + SOA_RDATA_SIZE
    private const val DNSSEC_OK_FLAG = 0x8000L
    private const val DNS_FLAG_QR = 0x80
    private const val RCODE_NOERROR = 0
    private const val RCODE_FORMERR = 1
    private const val RCODE_SERVFAIL = 2
    private const val RCODE_NXDOMAIN = 3
    private const val RCODE_NOTIMP = 4
    private const val RCODE_REFUSED = 5

    data class DnsQuestion(
        val name: String,
        val type: Int,
        val qclass: Int,
        val dnssecOk: Boolean,
        val checkingDisabled: Boolean
    )

    data class ResponseTtlMetadata(
        val ttlOffsets: IntArray,
        val minTtlSeconds: Long
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is ResponseTtlMetadata) return false
            return ttlOffsets.contentEquals(other.ttlOffsets) &&
                    minTtlSeconds == other.minTtlSeconds
        }

        override fun hashCode(): Int {
            var result = ttlOffsets.contentHashCode()
            result = 31 * result + minTtlSeconds.hashCode()
            return result
        }
    }

    fun extractQuestion(query: ByteArray): DnsQuestion? {
        if (query.size < HEADER_LEN + 5) return null
        val qdCount = readShort(query, 4)
        if (qdCount != 1) return null

        val qname = readQueryName(query) ?: return null
        if (qname.endOffset + 4 > query.size) return null

        val checkingDisabled = (query[3].toInt() and 0x10) != 0
        return DnsQuestion(
            name = qname.name,
            type = readShort(query, qname.endOffset),
            qclass = readShort(query, qname.endOffset + 2),
            dnssecOk = hasDnssecOk(query, qname.endOffset + 4),
            checkingDisabled = checkingDisabled
        )
    }

    /**
     * Extracts the normalized (lowercased) QNAME from a DNS query, e.g.
     * "www.example.com". Only uncompressed query names are supported; returns
     * null on compression pointers or malformed input.
     */
    fun extractQueryName(query: ByteArray): String? {
        extractQuestion(query)?.let { return it.name }
        if (query.size < HEADER_LEN + 5) return null
        return readQueryName(query)?.name
    }

    /**
     * Extracts the QTYPE from a DNS query.
     */
    fun extractQueryType(query: ByteArray): Int {
        extractQuestion(query)?.let { return it.type }
        if (query.size < HEADER_LEN + 5) return 0
        val qname = readQueryName(query) ?: return 0
        if (qname.endOffset + 4 > query.size) return 0
        return readShort(query, qname.endOffset)
    }

    /**
     * Builds a standard DNS query message (QDCOUNT=1, RD=1).
     *
     * @param qname query name, e.g. "www.example.com"
     * @param qtype query type, e.g. 1 (A) or 28 (AAAA)
     * @param transactionId transaction ID; when 0 a random value is generated
     */
    fun buildQuery(qname: String, qtype: Int, transactionId: Int = 0): ByteArray {
        val labels = qname.trim().lowercase().split('.').filter { it.isNotEmpty() }
        var questionLen = 1 // terminating zero
        labels.forEach { questionLen += 1 + it.length }
        questionLen += 4 // QTYPE + QCLASS

        val query = ByteArray(HEADER_LEN + questionLen)
        val id = if (transactionId == 0) (0..65535).random() else transactionId
        writeShort(query, 0, id)
        // Flags: RD=1
        query[2] = 0x01
        query[3] = 0x00
        // QDCOUNT = 1
        writeShort(query, 4, 1)
        // AN/NS/AR = 0
        writeShort(query, 6, 0)
        writeShort(query, 8, 0)
        writeShort(query, 10, 0)

        var offset = HEADER_LEN
        labels.forEach { label ->
            val bytes = label.toByteArray(Charsets.US_ASCII)
            query[offset++] = bytes.size.toByte()
            bytes.copyInto(query, offset)
            offset += bytes.size
        }
        query[offset++] = 0x00
        writeShort(query, offset, qtype)
        writeShort(query, offset + 2, 1) // QCLASS = IN
        return query
    }

    fun buildBlockedResponse(query: ByteArray, mode: BlockResponseMode): ByteArray {
        return runCatching {
            when (mode) {
                BlockResponseMode.NXDOMAIN -> buildNegativeResponse(query, RCODE_NXDOMAIN)
                BlockResponseMode.NODATA -> buildNegativeResponse(query, RCODE_NOERROR)
                BlockResponseMode.REFUSED -> buildRefusedResponse(query)
                BlockResponseMode.ZERO_ADDRESS -> buildZeroAddressResponse(query)
            }
        }.getOrElse {
            buildErrorResponse(query, RCODE_SERVFAIL)
        }
    }

    private fun buildZeroAddressResponse(query: ByteArray): ByteArray {
        val question = extractQuestion(query)
            ?: return buildErrorResponse(query, RCODE_SERVFAIL)
        if (question.qclass != CLASS_IN) {
            return buildNegativeResponse(query, RCODE_NOERROR)
        }

        val address = when (question.type) {
            TYPE_A -> ByteArray(4)
            TYPE_AAAA -> ByteArray(16)
            else -> return buildNegativeResponse(query, RCODE_NOERROR)
        }
        val questionEnd = questionEnd(query)
            ?: return buildErrorResponse(query, RCODE_SERVFAIL)
        val response = createResponse(query, questionEnd, RCODE_NOERROR, answerCount = 1)
        var offset = questionEnd
        writeNamePointer(response, offset)
        offset += 2
        writeShort(response, offset, question.type)
        writeShort(response, offset + 2, CLASS_IN)
        writeInt(response, offset + 4, BLOCK_RESPONSE_TTL_SECONDS)
        writeShort(response, offset + 8, address.size)
        address.copyInto(response, offset + 10)
        return response
    }

    private fun buildNegativeResponse(query: ByteArray, responseCode: Int): ByteArray {
        val questionEnd = questionEnd(query)
            ?: return buildErrorResponse(query, RCODE_SERVFAIL)
        val response = createResponse(
            query = query,
            questionEnd = questionEnd,
            responseCode = responseCode,
            authorityCount = 1,
            extraSize = SOA_RECORD_SIZE
        )
        writeSoaRecord(response, questionEnd)
        return response
    }

    private fun buildRefusedResponse(query: ByteArray): ByteArray {
        val questionEnd = questionEnd(query)
            ?: return buildErrorResponse(query, RCODE_SERVFAIL)
        return createResponse(query, questionEnd, RCODE_REFUSED)
    }

    private fun createResponse(
        query: ByteArray,
        questionEnd: Int,
        responseCode: Int,
        answerCount: Int = 0,
        authorityCount: Int = 0,
        extraSize: Int = answerRecordSize(query, answerCount)
    ): ByteArray {
        val response = ByteArray(questionEnd + extraSize)
        query.copyInto(response, 0, 0, questionEnd)
        writeResponseHeader(response, query, responseCode)
        writeShort(response, 4, 1)
        writeShort(response, 6, answerCount)
        writeShort(response, 8, authorityCount)
        writeShort(response, 10, 0)
        return response
    }

    private fun answerRecordSize(query: ByteArray, answerCount: Int): Int {
        if (answerCount == 0) return 0
        val question = extractQuestion(query) ?: return 0
        val addressSize = if (question.type == TYPE_AAAA) 16 else 4
        return RESOURCE_RECORD_HEADER_SIZE + addressSize
    }

    private fun buildErrorResponse(query: ByteArray, responseCode: Int): ByteArray {
        val response = ByteArray(HEADER_LEN)
        query.copyInto(response, 0, 0, minOf(query.size, 2))
        writeResponseHeader(response, query, responseCode)
        writeShort(response, 4, 0)
        writeShort(response, 6, 0)
        writeShort(response, 8, 0)
        writeShort(response, 10, 0)
        return response
    }

    private fun writeResponseHeader(response: ByteArray, query: ByteArray, responseCode: Int) {
        val requestFlagsHigh = query.getOrNull(2)?.toInt()?.and(0xFF) ?: 0
        val requestFlagsLow = query.getOrNull(3)?.toInt()?.and(0xFF) ?: 0
        response[2] = (DNS_FLAG_QR or (requestFlagsHigh and 0x79)).toByte()
        response[3] = (0x80 or (requestFlagsLow and 0x10) or (responseCode and 0x0F)).toByte()
    }

    private fun writeSoaRecord(response: ByteArray, start: Int) {
        var offset = start
        writeNamePointer(response, offset)
        offset += 2
        writeShort(response, offset, TYPE_SOA)
        writeShort(response, offset + 2, CLASS_IN)
        writeInt(response, offset + 4, BLOCK_RESPONSE_TTL_SECONDS)
        writeShort(response, offset + 8, SOA_RDATA_SIZE)
        offset = start + RESOURCE_RECORD_HEADER_SIZE

        response[offset++] = 0 // MNAME = root
        response[offset++] = 0 // RNAME = root
        writeInt(response, offset, 0)
        writeInt(response, offset + 4, 0)
        writeInt(response, offset + 8, 0)
        writeInt(response, offset + 12, 0)
        writeInt(response, offset + 16, BLOCK_RESPONSE_TTL_SECONDS)
    }

    private fun writeNamePointer(response: ByteArray, offset: Int) {
        response[offset] = 0xC0.toByte()
        response[offset + 1] = HEADER_LEN.toByte()
    }

    private fun questionEnd(query: ByteArray): Int? {
        if (query.size < HEADER_LEN || readShort(query, 4) != 1) return null
        val nameEnd = skipName(query, HEADER_LEN)
        if (nameEnd < 0 || nameEnd + 4 > query.size) return null
        return nameEnd + 4
    }

    /**
     * Returns whether a DNS response is successful (RCODE == NOERROR).
     */
    fun isSuccessResponse(response: ByteArray): Boolean {
        return responseCode(response) == RCODE_NOERROR
    }

    /**
     * Returns whether the message is a DNS response that can be forwarded to
     * the client.
     *
     * A non-zero RCODE (e.g. NXDOMAIN) is still a valid DNS response; this
     * only filters out short packets, query packets, and responses whose
     * transaction ID does not match the original query.
     */
    fun isUsableUpstreamResponse(response: ByteArray, query: ByteArray): Boolean {
        return isDnsResponse(response) &&
                transactionId(response) == transactionId(query)
    }

    fun isDnsResponse(response: ByteArray): Boolean {
        if (response.size < HEADER_LEN) return false
        return (response[2].toInt() and DNS_FLAG_QR) != 0
    }

    fun responseCode(response: ByteArray): Int? {
        if (!isDnsResponse(response)) return null
        return response[3].toInt() and 0x0F
    }

    fun responseCodeLabel(response: ByteArray): String? {
        val code = responseCode(response) ?: return null
        val name = when (code) {
            RCODE_NOERROR -> "NOERROR"
            RCODE_FORMERR -> "FORMERR"
            RCODE_SERVFAIL -> "SERVFAIL"
            RCODE_NXDOMAIN -> "NXDOMAIN"
            RCODE_NOTIMP -> "NOTIMP"
            RCODE_REFUSED -> "REFUSED"
            else -> "RCODE $code"
        }
        return "$name ($code)"
    }

    fun transactionId(message: ByteArray): Int {
        if (message.size < 2) return -1
        return readShort(message, 0)
    }

    fun isTruncatedResponse(response: ByteArray): Boolean {
        if (response.size < HEADER_LEN) return false
        return (response[2].toInt() and 0x02) != 0
    }

    /**
     * Extracts the A / AAAA address records from the Answer section of a DNS
     * response.
     *
     * CNAMEs are only intermediate records in the response chain and are
     * skipped; only final address records are returned. Returns an empty list
     * on malformed input, a non-zero RCODE, or when no address record exists.
     */
    fun extractAddressRecords(response: ByteArray): List<InetAddress> {
        if (response.size < HEADER_LEN || !isSuccessResponse(response)) return emptyList()

        val qdCount = readShort(response, 4)
        val anCount = readShort(response, 6)
        if (anCount == 0) return emptyList()

        var offset = HEADER_LEN
        repeat(qdCount) {
            offset = skipName(response, offset)
            if (offset < 0) return emptyList()
            offset += 4 // QTYPE + QCLASS
            if (offset > response.size) return emptyList()
        }

        val addresses = mutableListOf<InetAddress>()
        repeat(anCount) {
            offset = skipName(response, offset)
            if (offset < 0 || offset + 10 > response.size) return emptyList()
            val rrType = readShort(response, offset)
            val rrClass = readShort(response, offset + 2)
            val rdLength = readShort(response, offset + 8)
            val rdataOffset = offset + 10
            if (rdataOffset + rdLength > response.size) return emptyList()

            if (rrClass == 1) {
                when (rrType) {
                    TYPE_A -> if (rdLength == 4) {
                        addresses.add(InetAddress.getByAddress(response.copyOfRange(rdataOffset, rdataOffset + 4)))
                    }
                    TYPE_AAAA -> if (rdLength == 16) {
                        addresses.add(InetAddress.getByAddress(response.copyOfRange(rdataOffset, rdataOffset + 16)))
                    }
                }
            }
            offset = rdataOffset + rdLength
        }

        return addresses.distinctBy { it.hostAddress }
    }

    fun withTransactionId(response: ByteArray, query: ByteArray): ByteArray {
        if (response.size < 2 || query.size < 2) return response.copyOf()
        val patched = response.copyOf()
        patched[0] = query[0]
        patched[1] = query[1]
        return patched
    }

    fun cacheLifetimeSeconds(response: ByteArray): Long {
        return extractResponseTtlMetadata(response)?.minTtlSeconds ?: 0L
    }

    fun extractResponseTtlMetadata(response: ByteArray): ResponseTtlMetadata? {
        val ttlOffsets = extractTtlOffsets(response)
        if (ttlOffsets.isEmpty()) return null
        return ResponseTtlMetadata(
            ttlOffsets = ttlOffsets.map { it.first }.toIntArray(),
            minTtlSeconds = ttlOffsets.minOf { it.second }.coerceAtLeast(0)
        )
    }

    /**
     * Extracts the offsets of every RR TTL field in a DNS response along with
     * the original TTL values.
     *
     * Scans the Answer / Authority / Additional sections and supports DNS
     * name compression. Returns an empty list on malformed input.
     */
    fun extractTtlOffsets(response: ByteArray): List<Pair<Int, Long>> {
        if (response.size < HEADER_LEN) return emptyList()

        val qdCount = readShort(response, 4)
        val anCount = readShort(response, 6)
        val nsCount = readShort(response, 8)
        val arCount = readShort(response, 10)
        val totalRecords = anCount + nsCount + arCount
        if (totalRecords == 0) return emptyList()

        var offset = HEADER_LEN

        // Skip the Question section
        repeat(qdCount) {
            offset = skipName(response, offset)
            if (offset < 0) return emptyList()
            offset += 4 // QTYPE + QCLASS
            if (offset > response.size) return emptyList()
        }

        val result = mutableListOf<Pair<Int, Long>>()
        repeat(totalRecords) {
            offset = skipName(response, offset)
            if (offset < 0) return emptyList()
            // TYPE(2) + CLASS(2) + TTL(4) + RDLENGTH(2) + RDATA(n)
            if (offset + 10 > response.size) return emptyList()
            val rrType = readShort(response, offset)
            // The OPT record (TYPE=41) TTL field is not a time-to-live; it holds
            // the extended RCODE + version + flags. It must be excluded from TTL
            // decrementing, or its typical value of 0 would permanently prevent
            // every cache hit.
            if (rrType != TYPE_OPT) {
                val ttlOffset = offset + 4
                val ttl = readUnsignedInt(response, ttlOffset)
                result.add(ttlOffset to ttl)
            }
            val rdLength = readShort(response, offset + 8)
            offset += 10 + rdLength
            if (offset > response.size) return emptyList()
        }

        return result
    }

    /**
     * Decrements the TTLs in a response by the time it has already been cached.
     *
     * @param response raw DNS response bytes
     * @param elapsedSeconds seconds the response has been cached
     * @return the response with TTLs decremented, or null if any RR's TTL has expired
     */
    fun patchResponseTtl(response: ByteArray, elapsedSeconds: Int): ByteArray? {
        val ttlOffsets = extractTtlOffsets(response)
        if (ttlOffsets.isEmpty()) return response.copyOf()

        val patched = response.copyOf()
        for ((offset, originalTtl) in ttlOffsets) {
            val remaining = originalTtl - elapsedSeconds
            if (remaining <= 0) return null
            writeInt(patched, offset, remaining)
        }
        return patched
    }

    fun patchResponseTtl(response: ByteArray, ttlOffsets: IntArray, remainingTtlSeconds: Long): ByteArray? {
        if (remainingTtlSeconds <= 0L) return null
        if (ttlOffsets.isEmpty()) return response.copyOf()
        val patched = response.copyOf()
        val ttl = remainingTtlSeconds.coerceAtMost(0xFFFF_FFFFL)
        ttlOffsets.forEach { offset ->
            if (offset < 0 || offset + 4 > patched.size) return null
            writeInt(patched, offset, ttl)
        }
        return patched
    }

    private fun hasDnssecOk(query: ByteArray, questionEnd: Int): Boolean {
        var offset = questionEnd
        val nsCount = readShort(query, 8)
        val arCount = readShort(query, 10)
        repeat(nsCount) {
            offset = skipName(query, offset)
            if (offset < 0 || offset + 10 > query.size) return false
            val rdLength = readShort(query, offset + 8)
            offset += 10 + rdLength
            if (offset > query.size) return false
        }
        repeat(arCount) {
            offset = skipName(query, offset)
            if (offset < 0 || offset + 10 > query.size) return false
            val rrType = readShort(query, offset)
            if (rrType == TYPE_OPT) {
                val ttl = readUnsignedInt(query, offset + 4)
                return (ttl and DNSSEC_OK_FLAG) != 0L
            }
            val rdLength = readShort(query, offset + 8)
            offset += 10 + rdLength
            if (offset > query.size) return false
        }
        return false
    }

    private data class QueryName(
        val name: String,
        val endOffset: Int
    )

    private fun readQueryName(query: ByteArray): QueryName? {
        val labels = mutableListOf<String>()
        var offset = HEADER_LEN
        while (offset < query.size) {
            val len = query[offset].toInt() and 0xFF
            if (len == 0) {
                offset++
                break
            }
            if (len >= 192) return null // compression pointer; never valid in a query
            if (offset + 1 + len > query.size) return null
            val label = String(query, offset + 1, len, Charsets.UTF_8).lowercase()
            labels.add(label)
            offset += 1 + len
        }
        if (labels.isEmpty()) return null
        return QueryName(
            name = labels.joinToString("."),
            endOffset = offset
        )
    }

    private fun skipName(buf: ByteArray, start: Int): Int {
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

    private fun readShort(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 8) or (buf[offset + 1].toInt() and 0xFF)
    }

    private fun writeShort(buf: ByteArray, offset: Int, value: Int) {
        buf[offset] = ((value shr 8) and 0xFF).toByte()
        buf[offset + 1] = (value and 0xFF).toByte()
    }

    private fun readInt(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 24) or
                ((buf[offset + 1].toInt() and 0xFF) shl 16) or
                ((buf[offset + 2].toInt() and 0xFF) shl 8) or
                (buf[offset + 3].toInt() and 0xFF)
    }

    private fun readUnsignedInt(buf: ByteArray, offset: Int): Long {
        return readInt(buf, offset).toLong() and 0xFFFF_FFFFL
    }

    private fun writeInt(buf: ByteArray, offset: Int, value: Long) {
        buf[offset] = (value ushr 24).toByte()
        buf[offset + 1] = (value ushr 16).toByte()
        buf[offset + 2] = (value ushr 8).toByte()
        buf[offset + 3] = value.toByte()
    }
}
