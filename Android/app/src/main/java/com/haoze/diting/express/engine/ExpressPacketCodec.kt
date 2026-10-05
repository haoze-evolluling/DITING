package com.haoze.diting.express.engine

import java.util.concurrent.atomic.AtomicInteger

/**
 * High-performance, zero-Android-dependency TUN packet codec for Express Mode.
 *
 * Handles IPv4/IPv6 decoding, UDP/TCP classification, non-53 TCP RST generation,
 * DNS response construction, and zero-allocation checksum calculations.
 */
object ExpressPacketCodec {

    const val PROTOCOL_TCP = 6
    const val PROTOCOL_UDP = 17
    const val DNS_PORT = 53

    private const val IPV4_MIN_HEADER_LEN = 20
    private const val IPV6_HEADER_LEN = 40
    private const val UDP_HEADER_LEN = 8
    private const val TCP_MIN_HEADER_LEN = 20
    private const val DNS_HEADER_LEN = 12

    private const val TCP_FLAG_FIN = 0x01
    private const val TCP_FLAG_SYN = 0x02
    private const val TCP_FLAG_RST = 0x04
    private const val TCP_FLAG_PSH = 0x08
    private const val TCP_FLAG_ACK = 0x10

    private const val DNS_TYPE_OPT = 41

    private val ipIdGenerator = AtomicInteger(1)

    fun nextIpId(): Int = ipIdGenerator.getAndIncrement() and 0xFFFF

    sealed class ParsedPacket {
        data class DnsUdpQuery(
            val isIpv6: Boolean, val srcIp: ByteArray, val dstIp: ByteArray,
            val srcPort: Int, val dstPort: Int, val dnsPayload: ByteArray
        ) : ParsedPacket() {
            override fun equals(other: Any?): Boolean = this === other || (other is DnsUdpQuery && isIpv6 == other.isIpv6 && srcIp.contentEquals(other.srcIp) && dstIp.contentEquals(other.dstIp) && srcPort == other.srcPort && dstPort == other.dstPort && dnsPayload.contentEquals(other.dnsPayload))
            override fun hashCode(): Int = 31 * (31 * srcIp.contentHashCode() + dstIp.contentHashCode()) + dnsPayload.contentHashCode()
        }

        data class DnsTcpPacket(
            val isIpv6: Boolean, val srcIp: ByteArray, val dstIp: ByteArray,
            val srcPort: Int, val dstPort: Int, val seqNumber: Long,
            val ackNumber: Long, val flags: Int, val window: Int, val payload: ByteArray
        ) : ParsedPacket() {
            override fun equals(other: Any?): Boolean = this === other || (other is DnsTcpPacket && isIpv6 == other.isIpv6 && srcIp.contentEquals(other.srcIp) && dstIp.contentEquals(other.dstIp) && srcPort == other.srcPort && dstPort == other.dstPort && seqNumber == other.seqNumber && ackNumber == other.ackNumber && flags == other.flags && window == other.window && payload.contentEquals(other.payload))
            override fun hashCode(): Int = 31 * (31 * srcIp.contentHashCode() + dstIp.contentHashCode()) + payload.contentHashCode()
        }

        data class NonDnsTcpPacket(
            val isIpv6: Boolean, val srcIp: ByteArray, val dstIp: ByteArray,
            val srcPort: Int, val dstPort: Int, val seqNumber: Long,
            val ackNumber: Long, val flags: Int, val window: Int, val payloadLength: Int
        ) : ParsedPacket() {
            override fun equals(other: Any?): Boolean = this === other || (other is NonDnsTcpPacket && isIpv6 == other.isIpv6 && srcIp.contentEquals(other.srcIp) && dstIp.contentEquals(other.dstIp) && srcPort == other.srcPort && dstPort == other.dstPort && seqNumber == other.seqNumber && ackNumber == other.ackNumber && flags == other.flags && window == other.window && payloadLength == other.payloadLength)
            override fun hashCode(): Int = 31 * (31 * srcIp.contentHashCode() + dstIp.contentHashCode()) + payloadLength
        }

        data class DiscardPacket(
            val isIpv6: Boolean, val protocol: Int, val reason: String
        ) : ParsedPacket()
    }

    fun parse(packet: ByteArray, offset: Int = 0, length: Int = packet.size - offset): ParsedPacket? {
        if (length < IPV4_MIN_HEADER_LEN) return null
        val version = (packet[offset].toInt() ushr 4) and 0x0F
        return when (version) {
            4 -> parseIPv4(packet, offset, length)
            6 -> parseIPv6(packet, offset, length)
            else -> null
        }
    }

    private fun parseIPv4(packet: ByteArray, offset: Int, length: Int): ParsedPacket? {
        val ihl = (packet[offset].toInt() and 0x0F) * 4
        if (ihl < IPV4_MIN_HEADER_LEN || length < ihl) return null

        val totalLength = readUint16(packet, offset + 2)
        if (totalLength < ihl || totalLength > length) return null

        val fragField = readUint16(packet, offset + 6)
        val fragOffset = fragField and 0x1FFF
        val moreFragments = (fragField and 0x2000) != 0
        if (fragOffset != 0 || moreFragments) {
            val reason = if (fragOffset != 0) "Non-first fragment" else "Fragmented datagram (MF=1)"
            return ParsedPacket.DiscardPacket(false, packet[offset + 9].toInt() and 0xFF, reason)
        }

        val protocol = packet[offset + 9].toInt() and 0xFF
        val srcIp = packet.copyOfRange(offset + 12, offset + 16)
        val dstIp = packet.copyOfRange(offset + 16, offset + 20)

        val l4Offset = offset + ihl
        val l4Length = totalLength - ihl
        return parseL4(packet, l4Offset, l4Length, isIpv6 = false, srcIp = srcIp, dstIp = dstIp, protocol = protocol)
    }

    private fun parseIPv6(packet: ByteArray, offset: Int, length: Int): ParsedPacket? {
        if (length < IPV6_HEADER_LEN) return null
        val payloadLen = readUint16(packet, offset + 4)
        val totalLength = IPV6_HEADER_LEN + payloadLen
        if (length < totalLength) return null

        val srcIp = packet.copyOfRange(offset + 8, offset + 24)
        val dstIp = packet.copyOfRange(offset + 24, offset + 40)

        var currentHeader = packet[offset + 6].toInt() and 0xFF
        var currentOffset = offset + IPV6_HEADER_LEN
        val endOffset = offset + totalLength

        while (currentOffset < endOffset) {
            when (currentHeader) {
                PROTOCOL_UDP, PROTOCOL_TCP -> {
                    val l4Length = endOffset - currentOffset
                    return parseL4(packet, currentOffset, l4Length, isIpv6 = true, srcIp = srcIp, dstIp = dstIp, protocol = currentHeader)
                }
                44 -> { // Fragment Header (8 bytes)
                    if (currentOffset + 8 > endOffset) return null
                    val fragOffsetFlags = readUint16(packet, currentOffset + 2)
                    val fragOffset = (fragOffsetFlags and 0xFFF8) ushr 3
                    val mFlag = (fragOffsetFlags and 0x0001) != 0
                    if (fragOffset != 0 || mFlag) {
                        val reason = if (fragOffset != 0) "Non-first IPv6 fragment" else "Fragmented IPv6 packet (M=1)"
                        return ParsedPacket.DiscardPacket(true, 44, reason)
                    }
                    currentHeader = packet[currentOffset].toInt() and 0xFF
                    currentOffset += 8
                }
                0, 43, 60, 135 -> { // Hop-by-hop, Routing, Dest Options, Mobility
                    if (currentOffset + 2 > endOffset) return null
                    val extLen = ((packet[currentOffset + 1].toInt() and 0xFF) + 1) * 8
                    if (currentOffset + extLen > endOffset) return null
                    currentHeader = packet[currentOffset].toInt() and 0xFF
                    currentOffset += extLen
                }
                51 -> { // Authentication Header
                    if (currentOffset + 2 > endOffset) return null
                    val extLen = ((packet[currentOffset + 1].toInt() and 0xFF) + 2) * 4
                    if (currentOffset + extLen > endOffset) return null
                    currentHeader = packet[currentOffset].toInt() and 0xFF
                    currentOffset += extLen
                }
                else -> {
                    return ParsedPacket.DiscardPacket(true, currentHeader, "Unsupported IPv6 extension header $currentHeader")
                }
            }
        }
        return null
    }

    private fun parseL4(
        packet: ByteArray,
        l4Offset: Int,
        l4Length: Int,
        isIpv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        protocol: Int
    ): ParsedPacket? {
        when (protocol) {
            PROTOCOL_UDP -> {
                if (l4Length < UDP_HEADER_LEN) return null
                val srcPort = readUint16(packet, l4Offset)
                val dstPort = readUint16(packet, l4Offset + 2)
                val udpLen = readUint16(packet, l4Offset + 4)
                if (udpLen < UDP_HEADER_LEN || udpLen > l4Length) return null
                val payload = packet.copyOfRange(l4Offset + UDP_HEADER_LEN, l4Offset + udpLen)
                return if (dstPort == DNS_PORT) {
                    ParsedPacket.DnsUdpQuery(isIpv6, srcIp, dstIp, srcPort, dstPort, payload)
                } else {
                    ParsedPacket.DiscardPacket(isIpv6, PROTOCOL_UDP, "Non-DNS UDP port $dstPort")
                }
            }
            PROTOCOL_TCP -> {
                if (l4Length < TCP_MIN_HEADER_LEN) return null
                val srcPort = readUint16(packet, l4Offset)
                val dstPort = readUint16(packet, l4Offset + 2)
                val seq = readUint32(packet, l4Offset + 4)
                val ack = readUint32(packet, l4Offset + 8)
                val dataOffset = ((packet[l4Offset + 12].toInt() ushr 4) and 0x0F) * 4
                if (dataOffset < TCP_MIN_HEADER_LEN || dataOffset > l4Length) return null
                val flags = packet[l4Offset + 13].toInt() and 0xFF
                val window = readUint16(packet, l4Offset + 14)
                val payload = packet.copyOfRange(l4Offset + dataOffset, l4Offset + l4Length)
                return if (dstPort == DNS_PORT) {
                    ParsedPacket.DnsTcpPacket(isIpv6, srcIp, dstIp, srcPort, dstPort, seq, ack, flags, window, payload)
                } else {
                    ParsedPacket.NonDnsTcpPacket(isIpv6, srcIp, dstIp, srcPort, dstPort, seq, ack, flags, window, payload.size)
                }
            }
            else -> return ParsedPacket.DiscardPacket(isIpv6, protocol, "Non UDP/TCP protocol")
        }
    }

    /**
     * Builds an RFC 793 TCP RST packet in response to a non-53 TCP packet entering TUN.
     */
    fun buildTcpReset(
        isIpv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        seqNumber: Long,
        ackNumber: Long,
        flags: Int,
        payloadLength: Int = 0,
        outBuffer: ByteArray? = null
    ): ByteArray? {
        if ((flags and TCP_FLAG_RST) != 0) return null

        val hasAck = (flags and TCP_FLAG_ACK) != 0
        val respSeq: Long
        val respAck: Long
        val respFlags: Int

        if (hasAck) {
            respSeq = ackNumber
            respAck = 0L
            respFlags = TCP_FLAG_RST
        } else {
            respSeq = 0L
            val synCount = if ((flags and TCP_FLAG_SYN) != 0) 1 else 0
            val finCount = if ((flags and TCP_FLAG_FIN) != 0) 1 else 0
            respAck = (seqNumber + payloadLength + synCount + finCount) and 0xFFFF_FFFFL
            respFlags = TCP_FLAG_RST or TCP_FLAG_ACK
        }

        val ipHeaderLen = if (isIpv6) IPV6_HEADER_LEN else IPV4_MIN_HEADER_LEN
        val totalLen = ipHeaderLen + TCP_MIN_HEADER_LEN
        val buffer = if (outBuffer != null && outBuffer.size >= totalLen) outBuffer else ByteArray(totalLen)

        if (!isIpv6) {
            encodeIPv4Header(buffer, totalLen, PROTOCOL_TCP, srcIp = dstIp, dstIp = srcIp, id = nextIpId())
        } else {
            encodeIPv6Header(buffer, TCP_MIN_HEADER_LEN, PROTOCOL_TCP, srcIp = dstIp, dstIp = srcIp)
        }

        val tcpOffset = ipHeaderLen
        writeUint16(buffer, tcpOffset, dstPort)
        writeUint16(buffer, tcpOffset + 2, srcPort)
        writeUint32(buffer, tcpOffset + 4, respSeq)
        writeUint32(buffer, tcpOffset + 8, respAck)
        buffer[tcpOffset + 12] = (5 shl 4).toByte() // 20 bytes
        buffer[tcpOffset + 13] = respFlags.toByte()
        writeUint16(buffer, tcpOffset + 14, 0) // Window = 0
        writeUint16(buffer, tcpOffset + 16, 0) // Checksum placeholder
        writeUint16(buffer, tcpOffset + 18, 0) // Urgent pointer

        val tcpChecksum = computeL4Checksum(
            isIpv6 = isIpv6,
            srcIp = dstIp,
            dstIp = srcIp,
            protocol = PROTOCOL_TCP,
            l4Length = TCP_MIN_HEADER_LEN,
            packet = buffer,
            l4Offset = tcpOffset
        )
        writeUint16(buffer, tcpOffset + 16, tcpChecksum)

        return if (buffer === outBuffer && buffer.size == totalLen) buffer else buffer.copyOf(totalLen)
    }

    fun buildTcpReset(incoming: ParsedPacket.NonDnsTcpPacket, outBuffer: ByteArray? = null): ByteArray? =
        buildTcpReset(
            isIpv6 = incoming.isIpv6,
            srcIp = incoming.srcIp,
            dstIp = incoming.dstIp,
            srcPort = incoming.srcPort,
            dstPort = incoming.dstPort,
            seqNumber = incoming.seqNumber,
            ackNumber = incoming.ackNumber,
            flags = incoming.flags,
            payloadLength = incoming.payloadLength,
            outBuffer = outBuffer
        )

    /**
     * Encodes an IP + UDP response packet into [outBuffer] at [outOffset] without allocations.
     * Returns the total packet length written, or -1 if [outBuffer] is too small.
     */
    fun encodeUdpResponse(
        isIpv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        dnsPayload: ByteArray,
        payloadOffset: Int = 0,
        payloadLen: Int = dnsPayload.size - payloadOffset,
        ipId: Int = nextIpId(),
        ttl: Int = 64,
        outBuffer: ByteArray,
        outOffset: Int = 0
    ): Int {
        val ipHeaderLen = if (isIpv6) IPV6_HEADER_LEN else IPV4_MIN_HEADER_LEN
        val udpTotalLen = UDP_HEADER_LEN + payloadLen
        val totalLen = ipHeaderLen + udpTotalLen
        if (outBuffer.size < outOffset + totalLen) return -1

        if (!isIpv6) {
            encodeIPv4Header(outBuffer, totalLen, PROTOCOL_UDP, srcIp = srcIp, dstIp = dstIp, id = ipId, ttl = ttl, offset = outOffset)
        } else {
            encodeIPv6Header(outBuffer, udpTotalLen, PROTOCOL_UDP, srcIp = srcIp, dstIp = dstIp, hopLimit = ttl, offset = outOffset)
        }

        val udpOffset = outOffset + ipHeaderLen
        writeUint16(outBuffer, udpOffset, srcPort)
        writeUint16(outBuffer, udpOffset + 2, dstPort)
        writeUint16(outBuffer, udpOffset + 4, udpTotalLen)
        writeUint16(outBuffer, udpOffset + 6, 0) // Checksum placeholder

        System.arraycopy(dnsPayload, payloadOffset, outBuffer, udpOffset + UDP_HEADER_LEN, payloadLen)

        val udpChecksum = computeL4Checksum(
            isIpv6 = isIpv6,
            srcIp = srcIp,
            dstIp = dstIp,
            protocol = PROTOCOL_UDP,
            l4Length = udpTotalLen,
            packet = outBuffer,
            l4Offset = udpOffset
        )
        writeUint16(outBuffer, udpOffset + 6, udpChecksum)
        return totalLen
    }

    /**
     * Builds an IP + UDP response packet containing [dnsPayload].
     */
    fun buildUdpResponse(
        isIpv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        dnsPayload: ByteArray,
        payloadOffset: Int = 0,
        payloadLen: Int = dnsPayload.size - payloadOffset,
        ipId: Int = nextIpId(),
        ttl: Int = 64,
        outBuffer: ByteArray? = null
    ): ByteArray {
        val ipHeaderLen = if (isIpv6) IPV6_HEADER_LEN else IPV4_MIN_HEADER_LEN
        val totalLen = ipHeaderLen + UDP_HEADER_LEN + payloadLen
        val buffer = if (outBuffer != null && outBuffer.size >= totalLen) outBuffer else ByteArray(totalLen)
        encodeUdpResponse(isIpv6, srcIp, dstIp, srcPort, dstPort, dnsPayload, payloadOffset, payloadLen, ipId, ttl, buffer, 0)
        return if (buffer === outBuffer && buffer.size == totalLen) buffer else buffer.copyOf(totalLen)
    }

    private fun encodeIPv4Header(
        buffer: ByteArray, totalLen: Int, protocol: Int,
        srcIp: ByteArray, dstIp: ByteArray, id: Int, ttl: Int = 64, offset: Int = 0
    ) {
        buffer[offset] = 0x45.toByte() // Version 4, IHL 5
        buffer[offset + 1] = 0x00.toByte() // ToS
        writeUint16(buffer, offset + 2, totalLen)
        writeUint16(buffer, offset + 4, id)
        writeUint16(buffer, offset + 6, 0x4000) // DF bit set
        buffer[offset + 8] = ttl.toByte()
        buffer[offset + 9] = protocol.toByte()
        writeUint16(buffer, offset + 10, 0) // Checksum placeholder
        System.arraycopy(srcIp, 0, buffer, offset + 12, 4)
        System.arraycopy(dstIp, 0, buffer, offset + 16, 4)

        val csum = calculateInternetChecksum(buffer, offset, IPV4_MIN_HEADER_LEN)
        writeUint16(buffer, offset + 10, csum)
    }

    private fun encodeIPv6Header(
        buffer: ByteArray, payloadLen: Int, nextHeader: Int,
        srcIp: ByteArray, dstIp: ByteArray, hopLimit: Int = 64, offset: Int = 0
    ) {
        buffer[offset] = 0x60.toByte()
        buffer[offset + 1] = 0x00.toByte()
        buffer[offset + 2] = 0x00.toByte()
        buffer[offset + 3] = 0x00.toByte()
        writeUint16(buffer, offset + 4, payloadLen)
        buffer[offset + 6] = nextHeader.toByte()
        buffer[offset + 7] = hopLimit.toByte()
        System.arraycopy(srcIp, 0, buffer, offset + 8, 16)
        System.arraycopy(dstIp, 0, buffer, offset + 24, 16)
    }

    fun calculateInternetChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = offset
        val end = offset + length
        while (i + 1 < end) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) {
            sum += (data[i].toInt() and 0xFF) shl 8
        }
        while (sum > 0xFFFFL) {
            sum = (sum ushr 16) + (sum and 0xFFFFL)
        }
        return (sum.inv() and 0xFFFFL).toInt()
    }

    fun computeL4Checksum(
        isIpv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        protocol: Int,
        l4Length: Int,
        packet: ByteArray,
        l4Offset: Int
    ): Int {
        var sum = 0L
        val ipLen = if (isIpv6) 16 else 4
        for (i in 0 until ipLen step 2) {
            sum += ((srcIp[i].toInt() and 0xFF) shl 8) or (srcIp[i + 1].toInt() and 0xFF)
            sum += ((dstIp[i].toInt() and 0xFF) shl 8) or (dstIp[i + 1].toInt() and 0xFF)
        }

        if (!isIpv6) {
            sum += protocol
            sum += l4Length
        } else {
            sum += (l4Length ushr 16) and 0xFFFF
            sum += l4Length and 0xFFFF
            sum += protocol
        }

        var i = l4Offset
        val end = l4Offset + l4Length
        while (i + 1 < end) {
            sum += ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) {
            sum += (packet[i].toInt() and 0xFF) shl 8
        }

        while (sum > 0xFFFFL) {
            sum = (sum ushr 16) + (sum and 0xFFFFL)
        }
        val res = (sum.inv() and 0xFFFFL).toInt()
        return if (res == 0) 0xFFFF else res
    }

    /**
     * Decrements all RR TTLs in [dnsPayload] by [elapsedSeconds].
     * Returns null if any RR has expired (remaining TTL <= 0).
     * If [elapsedSeconds] == 0, returns identical copy idempotently.
     */
    fun patchDnsPayloadTtl(dnsPayload: ByteArray, elapsedSeconds: Int): ByteArray? {
        if (dnsPayload.size < DNS_HEADER_LEN || elapsedSeconds < 0) return null
        val offsetsAndTtls = extractRrTtls(dnsPayload)
        if (offsetsAndTtls.isEmpty() || elapsedSeconds == 0) {
            return dnsPayload.copyOf()
        }

        val patched = dnsPayload.copyOf()
        for ((offset, originalTtl) in offsetsAndTtls) {
            val remaining = originalTtl - elapsedSeconds
            if (remaining <= 0) return null
            writeUint32(patched, offset, remaining)
        }
        return patched
    }

    /**
     * Overwrites all RR TTLs in [dnsPayload] with [newTtlSeconds].
     */
    fun overwriteDnsPayloadTtl(dnsPayload: ByteArray, newTtlSeconds: Long): ByteArray? {
        if (dnsPayload.size < DNS_HEADER_LEN || newTtlSeconds <= 0L) return null
        val offsetsAndTtls = extractRrTtls(dnsPayload)
        if (offsetsAndTtls.isEmpty()) return dnsPayload.copyOf()

        val patched = dnsPayload.copyOf()
        val ttl = newTtlSeconds.coerceAtMost(0xFFFF_FFFFL)
        for ((offset, _) in offsetsAndTtls) {
            writeUint32(patched, offset, ttl)
        }
        return patched
    }

    /**
     * Extracts minimum TTL in seconds from Answer/Authority/Additional sections (skipping OPT).
     */
    fun extractMinDnsTtl(dnsPayload: ByteArray): Long? {
        val list = extractRrTtls(dnsPayload)
        if (list.isEmpty()) return null
        return list.minOf { it.second }
    }

    private fun extractRrTtls(payload: ByteArray): List<Pair<Int, Long>> {
        if (payload.size < DNS_HEADER_LEN) return emptyList()
        val qdCount = readUint16(payload, 4)
        val anCount = readUint16(payload, 6)
        val nsCount = readUint16(payload, 8)
        val arCount = readUint16(payload, 10)
        val totalRrs = anCount + nsCount + arCount
        if (totalRrs == 0) return emptyList()

        var offset = DNS_HEADER_LEN
        repeat(qdCount) {
            offset = skipDnsName(payload, offset)
            if (offset < 0 || offset + 4 > payload.size) return emptyList()
            offset += 4
        }

        val result = mutableListOf<Pair<Int, Long>>()
        repeat(totalRrs) {
            offset = skipDnsName(payload, offset)
            if (offset < 0 || offset + 10 > payload.size) return emptyList()
            val rrType = readUint16(payload, offset)
            val ttlOffset = offset + 4
            val ttl = readUint32(payload, ttlOffset)
            val rdLength = readUint16(payload, offset + 8)
            if (rrType != DNS_TYPE_OPT) {
                result.add(ttlOffset to ttl)
            }
            offset += 10 + rdLength
            if (offset > payload.size) return emptyList()
        }
        return result
    }

    private fun skipDnsName(buf: ByteArray, start: Int): Int {
        var offset = start
        var jumped = false
        var current = start
        var steps = 128

        while (steps-- > 0) {
            if (offset >= buf.size) return -1
            val len = buf[offset].toInt() and 0xFF
            if (len == 0) {
                offset++
                break
            }
            if (len >= 192) {
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

    fun readUint16(buf: ByteArray, offset: Int): Int =
        ((buf[offset].toInt() and 0xFF) shl 8) or (buf[offset + 1].toInt() and 0xFF)

    fun writeUint16(buf: ByteArray, offset: Int, value: Int) {
        buf[offset] = ((value ushr 8) and 0xFF).toByte()
        buf[offset + 1] = (value and 0xFF).toByte()
    }

    fun readUint32(buf: ByteArray, offset: Int): Long =
        (((buf[offset].toLong() and 0xFFL) shl 24) or
                ((buf[offset + 1].toLong() and 0xFFL) shl 16) or
                ((buf[offset + 2].toLong() and 0xFFL) shl 8) or
                (buf[offset + 3].toLong() and 0xFFL)) and 0xFFFF_FFFFL

    fun writeUint32(buf: ByteArray, offset: Int, value: Long) {
        buf[offset] = ((value ushr 24) and 0xFFL).toByte()
        buf[offset + 1] = ((value ushr 16) and 0xFFL).toByte()
        buf[offset + 2] = ((value ushr 8) and 0xFFL).toByte()
        buf[offset + 3] = (value and 0xFFL).toByte()
    }
}
