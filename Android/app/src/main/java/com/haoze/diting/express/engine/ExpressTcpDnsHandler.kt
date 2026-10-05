package com.haoze.diting.express.engine

import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Minimal DNS-over-TCP terminator for Express Mode.
 *
 * Handles 3-way handshake (SYN -> SYN-ACK), TCP stream reassembly,
 * 2-byte length framed DNS message dispatch to ExpressDnsEngine,
 * response segmentation, FIN/RST termination, and basic retransmission.
 *
 * Fully JVM testable with zero android.* imports.
 */
class ExpressTcpDnsHandler(
    private val engine: ExpressDnsEngine,
    private val mss: Int = DEFAULT_MSS
) {

    companion object {
        const val DEFAULT_MSS = 1300
        private const val RETRANSMIT_TIMEOUT_MS = 1000L
        private const val MAX_RETRANSMITS = 3
    }

    enum class TcpState {
        SYN_RECEIVED,
        ESTABLISHED,
        CLOSED
    }

    data class ConnKey(
        val isIpv6: Boolean,
        val clientIp: String,
        val serverIp: String,
        val clientPort: Int,
        val serverPort: Int
    )

    data class SentSegment(
        val packet: ByteArray,
        val seq: Long,
        val len: Int,
        var sendTimeMs: Long,
        var retries: Int = 0
    )

    class TcpConnection(
        val key: ConnKey,
        val clientRawIp: ByteArray,
        val serverRawIp: ByteArray,
        var state: TcpState,
        var localSeq: Long,
        var remoteSeq: Long
    ) {
        val rxBuffer = ByteArrayOutputStream()
        var expectedDnsLength: Int = -1
        var lastActiveTimeMs: Long = System.currentTimeMillis()
        val unackedSegments = mutableListOf<SentSegment>()
    }

    private val connections = ConcurrentHashMap<ConnKey, TcpConnection>()

    suspend fun handlePacket(packet: ExpressPacketCodec.ParsedPacket.DnsTcpPacket): List<ByteArray> {
        val clientIpStr = formatIp(packet.srcIp)
        val serverIpStr = formatIp(packet.dstIp)
        val key = ConnKey(packet.isIpv6, clientIpStr, serverIpStr, packet.srcPort, packet.dstPort)

        // Handle RST
        if ((packet.flags and 0x04) != 0) {
            connections.remove(key)
            return emptyList()
        }

        // Handle SYN
        if ((packet.flags and 0x02) != 0) {
            val localInitialSeq = (ExpressPacketCodec.nextIpId().toLong() shl 16) or 0x1000L
            val remoteInitialSeq = (packet.seqNumber + 1) and 0xFFFF_FFFFL
            val conn = TcpConnection(
                key = key,
                clientRawIp = packet.srcIp,
                serverRawIp = packet.dstIp,
                state = TcpState.SYN_RECEIVED,
                localSeq = localInitialSeq,
                remoteSeq = remoteInitialSeq
            )
            connections[key] = conn

            val synAck = buildPacket(
                conn = conn,
                flags = 0x12, // SYN | ACK
                seq = conn.localSeq,
                ack = conn.remoteSeq,
                payload = ByteArray(0)
            )
            conn.localSeq = (conn.localSeq + 1) and 0xFFFF_FFFFL
            return listOf(synAck)
        }

        val conn = connections[key] ?: run {
            if ((packet.flags and 0x04) != 0) return emptyList()
            val rst = ExpressPacketCodec.buildTcpReset(
                isIpv6 = packet.isIpv6,
                srcIp = packet.srcIp,
                dstIp = packet.dstIp,
                srcPort = packet.srcPort,
                dstPort = packet.dstPort,
                seqNumber = packet.seqNumber,
                ackNumber = packet.ackNumber,
                flags = packet.flags,
                payloadLength = packet.payload.size
            )
            return if (rst != null) listOf(rst) else emptyList()
        }
        conn.lastActiveTimeMs = System.currentTimeMillis()
        if (conn.state == TcpState.SYN_RECEIVED) {
            conn.state = TcpState.ESTABLISHED
        }

        // Acknowledge unacked segments if client ACK covers them (with 32-bit wrap handling)
        if ((packet.flags and 0x10) != 0) {
            val clientAck = packet.ackNumber
            synchronized(conn.unackedSegments) {
                conn.unackedSegments.removeAll { seg ->
                    val segEnd = (seg.seq + seg.len) and 0xFFFF_FFFFL
                    (clientAck - segEnd).toInt() >= 0
                }
            }
        }

        val responses = mutableListOf<ByteArray>()

        // Handle TCP payload (checking for duplicate / retransmitted segments)
        if (packet.payload.isNotEmpty()) {
            val segEnd = (packet.seqNumber + packet.payload.size) and 0xFFFF_FFFFL
            val diff = (segEnd - conn.remoteSeq).toInt()
            if (diff <= 0) {
                // Duplicate / retransmitted payload already processed; send ACK without corrupting rxBuffer
                val ackPacket = buildPacket(
                    conn = conn,
                    flags = 0x10, // ACK
                    seq = conn.localSeq,
                    ack = conn.remoteSeq,
                    payload = ByteArray(0)
                )
                responses.add(ackPacket)
            } else {
                val offset = (conn.remoteSeq - packet.seqNumber).toInt()
                if (offset in 0 until packet.payload.size) {
                    val newBytes = packet.payload.copyOfRange(offset, packet.payload.size)
                    conn.remoteSeq = segEnd
                    conn.rxBuffer.write(newBytes)
                } else if (offset < 0) {
                    // Out-of-order gap; ask for expected remoteSeq
                    val ackPacket = buildPacket(
                        conn = conn,
                        flags = 0x10,
                        seq = conn.localSeq,
                        ack = conn.remoteSeq,
                        payload = ByteArray(0)
                    )
                    responses.add(ackPacket)
                }
            }
        }

        var bufferBytes = conn.rxBuffer.toByteArray()

        while (true) {
            if (conn.expectedDnsLength == -1 && bufferBytes.size >= 2) {
                conn.expectedDnsLength = ((bufferBytes[0].toInt() and 0xFF) shl 8) or (bufferBytes[1].toInt() and 0xFF)
            }

            if (conn.expectedDnsLength != -1 && bufferBytes.size >= 2 + conn.expectedDnsLength) {
                val dnsQuery = bufferBytes.copyOfRange(2, 2 + conn.expectedDnsLength)
                val remaining = bufferBytes.copyOfRange(2 + conn.expectedDnsLength, bufferBytes.size)
                conn.rxBuffer.reset()
                conn.rxBuffer.write(remaining)
                bufferBytes = remaining
                conn.expectedDnsLength = -1

                // Resolve DNS query
                val dnsResponse = engine.resolve(dnsQuery)
                val framed = ByteArray(2 + dnsResponse.size)
                framed[0] = (dnsResponse.size ushr 8).toByte()
                framed[1] = (dnsResponse.size and 0xFF).toByte()
                System.arraycopy(dnsResponse, 0, framed, 2, dnsResponse.size)

                // Segment response into TCP MSS chunks
                var offset = 0
                while (offset < framed.size) {
                    val chunkSize = minOf(mss, framed.size - offset)
                    val chunk = framed.copyOfRange(offset, offset + chunkSize)
                    val isLast = offset + chunkSize == framed.size
                    val flags = if (isLast) 0x18 else 0x10 // PSH|ACK vs ACK

                    val segmentPacket = buildPacket(
                        conn = conn,
                        flags = flags,
                        seq = conn.localSeq,
                        ack = conn.remoteSeq,
                        payload = chunk
                    )

                    synchronized(conn.unackedSegments) {
                        conn.unackedSegments.add(
                            SentSegment(
                                packet = segmentPacket,
                                seq = conn.localSeq,
                                len = chunkSize,
                                sendTimeMs = System.currentTimeMillis()
                            )
                        )
                    }
                    conn.localSeq = (conn.localSeq + chunkSize) and 0xFFFF_FFFFL
                    responses.add(segmentPacket)
                    offset += chunkSize
                }
            } else {
                break
            }
        }

        // Handle FIN (after payload processing so data sent with FIN is not discarded)
        if ((packet.flags and 0x01) != 0) {
            conn.remoteSeq = (conn.remoteSeq + 1) and 0xFFFF_FFFFL
            conn.state = TcpState.CLOSED
            connections.remove(key)
            val finAck = buildPacket(
                conn = conn,
                flags = 0x11, // FIN | ACK
                seq = conn.localSeq,
                ack = conn.remoteSeq,
                payload = ByteArray(0)
            )
            conn.localSeq = (conn.localSeq + 1) and 0xFFFF_FFFFL
            responses.add(finAck)
            return responses
        }

        // If no data response generated yet, send immediate ACK for received payload
        if (responses.isEmpty() && packet.payload.isNotEmpty()) {
            val ackPacket = buildPacket(
                conn = conn,
                flags = 0x10, // ACK
                seq = conn.localSeq,
                ack = conn.remoteSeq,
                payload = ByteArray(0)
            )
            responses.add(ackPacket)
        }

        return responses
    }

    fun checkRetransmissions(nowMs: Long = System.currentTimeMillis()): List<ByteArray> {
        val toResend = mutableListOf<ByteArray>()
        connections.values.forEach { conn ->
            synchronized(conn.unackedSegments) {
                val it = conn.unackedSegments.iterator()
                while (it.hasNext()) {
                    val seg = it.next()
                    if (nowMs - seg.sendTimeMs >= RETRANSMIT_TIMEOUT_MS) {
                        if (seg.retries >= MAX_RETRANSMITS) {
                            it.remove()
                        } else {
                            seg.retries++
                            seg.sendTimeMs = nowMs
                            toResend.add(seg.packet)
                        }
                    }
                }
            }
        }
        return toResend
    }

    fun pruneInactive(nowMs: Long = System.currentTimeMillis(), timeoutMs: Long = 30_000L) {
        connections.entries.removeIf { (_, conn) ->
            nowMs - conn.lastActiveTimeMs > timeoutMs || conn.state == TcpState.CLOSED
        }
    }

    private fun buildPacket(
        conn: TcpConnection,
        flags: Int,
        seq: Long,
        ack: Long,
        payload: ByteArray
    ): ByteArray {
        val isIpv6 = conn.key.isIpv6
        val ipHeaderLen = if (isIpv6) 40 else 20
        val tcpHeaderLen = 20
        val totalLen = ipHeaderLen + tcpHeaderLen + payload.size
        val packet = ByteArray(totalLen)

        if (!isIpv6) {
            packet[0] = 0x45
            ExpressPacketCodec.writeUint16(packet, 2, totalLen)
            ExpressPacketCodec.writeUint16(packet, 4, ExpressPacketCodec.nextIpId())
            ExpressPacketCodec.writeUint16(packet, 6, 0x4000) // DF
            packet[8] = 64 // TTL
            packet[9] = ExpressPacketCodec.PROTOCOL_TCP.toByte()
            System.arraycopy(conn.serverRawIp, 0, packet, 12, 4)
            System.arraycopy(conn.clientRawIp, 0, packet, 16, 4)
            val ipCsum = ExpressPacketCodec.calculateInternetChecksum(packet, 0, 20)
            ExpressPacketCodec.writeUint16(packet, 10, ipCsum)
        } else {
            packet[0] = 0x60
            ExpressPacketCodec.writeUint16(packet, 4, tcpHeaderLen + payload.size)
            packet[6] = ExpressPacketCodec.PROTOCOL_TCP.toByte()
            packet[7] = 64
            System.arraycopy(conn.serverRawIp, 0, packet, 8, 16)
            System.arraycopy(conn.clientRawIp, 0, packet, 24, 16)
        }

        val tcpOffset = ipHeaderLen
        ExpressPacketCodec.writeUint16(packet, tcpOffset, conn.key.serverPort)
        ExpressPacketCodec.writeUint16(packet, tcpOffset + 2, conn.key.clientPort)
        ExpressPacketCodec.writeUint32(packet, tcpOffset + 4, seq)
        ExpressPacketCodec.writeUint32(packet, tcpOffset + 8, ack)
        packet[tcpOffset + 12] = (5 shl 4).toByte()
        packet[tcpOffset + 13] = flags.toByte()
        ExpressPacketCodec.writeUint16(packet, tcpOffset + 14, 65535) // Window
        ExpressPacketCodec.writeUint16(packet, tcpOffset + 16, 0) // Placeholder
        ExpressPacketCodec.writeUint16(packet, tcpOffset + 18, 0) // Urgent

        if (payload.isNotEmpty()) {
            System.arraycopy(payload, 0, packet, tcpOffset + tcpHeaderLen, payload.size)
        }

        val tcpChecksum = ExpressPacketCodec.computeL4Checksum(
            isIpv6 = isIpv6,
            srcIp = conn.serverRawIp,
            dstIp = conn.clientRawIp,
            protocol = ExpressPacketCodec.PROTOCOL_TCP,
            l4Length = tcpHeaderLen + payload.size,
            packet = packet,
            l4Offset = tcpOffset
        )
        ExpressPacketCodec.writeUint16(packet, tcpOffset + 16, tcpChecksum)
        return packet
    }

    private fun formatIp(ip: ByteArray): String {
        return ip.joinToString(if (ip.size == 4) "." else ":") { (it.toInt() and 0xFF).toString() }
    }
}
