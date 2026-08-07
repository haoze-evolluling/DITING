package com.haoze.dnssr.vpn

import java.net.InetAddress

/**
 * 简化版 IPv4/IPv6 + UDP 数据包解析与构造工具。
 * 仅用于在 VPN 隧道中处理 DNS 查询与响应。
 */
object IpUdpPacket {

    private const val IP_PROTOCOL_UDP: Int = 17
    private const val UDP_HEADER_LEN = 8
    private const val IPV4_HEADER_LEN = 20
    private const val IPV6_HEADER_LEN = 40

    data class DnsPacketInfo(
        val version: Int,
        val sourceIp: InetAddress,
        val destIp: InetAddress,
        val sourcePort: Int,
        val destPort: Int,
        val dnsPayload: ByteArray
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is DnsPacketInfo) return false
            return version == other.version &&
                    sourceIp == other.sourceIp &&
                    destIp == other.destIp &&
                    sourcePort == other.sourcePort &&
                    destPort == other.destPort &&
                    dnsPayload.contentEquals(other.dnsPayload)
        }

        override fun hashCode(): Int {
            var result = version
            result = 31 * result + sourceIp.hashCode()
            result = 31 * result + destIp.hashCode()
            result = 31 * result + sourcePort
            result = 31 * result + destPort
            result = 31 * result + dnsPayload.contentHashCode()
            return result
        }
    }

    /**
     * 从原始 IP 数据包中提取 UDP DNS 信息。
     * 如果不是 IPv4/IPv6 UDP 包，或目的端口不是 53，返回 null。
     */
    fun parseDnsPacket(packet: ByteArray, length: Int): DnsPacketInfo? {
        return parseDnsPacket(packet, 0, length)
    }

    fun parseDnsPacket(packet: ByteArray, offset: Int, length: Int): DnsPacketInfo? {
        if (offset < 0 || length < 1 || offset + length > packet.size) return null
        val version = (packet[offset].toInt() and 0xF0) ushr 4
        return when (version) {
            4 -> parseIpv4(packet, offset, length)
            6 -> parseIpv6(packet, offset, length)
            else -> null
        }
    }

    /**
     * 根据收到的 DNS 查询包，构造包含 DNS 响应的 IP/UDP 数据包。
     * 源/目的地址与端口会自动交换。
     */
    fun buildResponsePacket(request: DnsPacketInfo, dnsResponse: ByteArray): ByteArray {
        return when (request.version) {
            4 -> buildIpv4Response(request, dnsResponse)
            6 -> buildIpv6Response(request, dnsResponse)
            else -> throw IllegalArgumentException("Unsupported IP version: ${request.version}")
        }
    }

    private fun parseIpv4(packet: ByteArray, offset: Int, length: Int): DnsPacketInfo? {
        if (length < IPV4_HEADER_LEN + UDP_HEADER_LEN) return null
        val ipHeaderLen = (packet[offset].toInt() and 0x0F) * 4
        if (ipHeaderLen < IPV4_HEADER_LEN || length < ipHeaderLen + UDP_HEADER_LEN) return null
        if (packet[offset + 9].toInt() and 0xFF != IP_PROTOCOL_UDP) return null

        val totalLen = readShort(packet, offset + 2)
        if (totalLen > length) return null
        if (totalLen < ipHeaderLen + UDP_HEADER_LEN) return null
        val packetEnd = offset + totalLen
        val udpOffset = offset + ipHeaderLen

        val sourceIp = InetAddress.getByAddress(packet.copyOfRange(offset + 12, offset + 16))
        val destIp = InetAddress.getByAddress(packet.copyOfRange(offset + 16, offset + 20))
        val sourcePort = readShort(packet, udpOffset)
        val destPort = readShort(packet, udpOffset + 2)
        val udpLen = readShort(packet, udpOffset + 4)
        val payloadLen = udpLen - UDP_HEADER_LEN
        val payloadOffset = udpOffset + UDP_HEADER_LEN
        if (payloadLen < 0 || payloadOffset + payloadLen > packetEnd) return null

        val payload = packet.copyOfRange(payloadOffset, payloadOffset + payloadLen)
        return DnsPacketInfo(4, sourceIp, destIp, sourcePort, destPort, payload)
    }

    private fun parseIpv6(packet: ByteArray, offset: Int, length: Int): DnsPacketInfo? {
        if (length < IPV6_HEADER_LEN + UDP_HEADER_LEN) return null
        if (packet[offset + 6].toInt() and 0xFF != IP_PROTOCOL_UDP) return null

        val payloadLen = readShort(packet, offset + 4)
        if (IPV6_HEADER_LEN + payloadLen > length) return null
        if (payloadLen < UDP_HEADER_LEN) return null
        val udpOffset = offset + IPV6_HEADER_LEN
        val udpLen = readShort(packet, udpOffset + 4)
        val dnsPayloadLen = udpLen - UDP_HEADER_LEN
        val payloadOffset = udpOffset + UDP_HEADER_LEN
        if (dnsPayloadLen < 0 || udpLen > payloadLen || payloadOffset + dnsPayloadLen > offset + length) return null

        val sourceIp = InetAddress.getByAddress(packet.copyOfRange(offset + 8, offset + 24))
        val destIp = InetAddress.getByAddress(packet.copyOfRange(offset + 24, offset + 40))
        val sourcePort = readShort(packet, udpOffset)
        val destPort = readShort(packet, udpOffset + 2)
        val payload = packet.copyOfRange(payloadOffset, payloadOffset + dnsPayloadLen)
        return DnsPacketInfo(6, sourceIp, destIp, sourcePort, destPort, payload)
    }

    private fun buildIpv4Response(request: DnsPacketInfo, dnsResponse: ByteArray): ByteArray {
        val udpLen = UDP_HEADER_LEN + dnsResponse.size
        val ipTotalLen = IPV4_HEADER_LEN + udpLen
        val packet = ByteArray(ipTotalLen)

        packet[0] = 0x45
        packet[1] = 0
        writeShort(packet, 2, ipTotalLen)
        writeShort(packet, 4, 0)
        writeShort(packet, 6, 0x4000)
        packet[8] = 64
        packet[9] = IP_PROTOCOL_UDP.toByte()
        request.destIp.address?.copyInto(packet, 12)
        request.sourceIp.address?.copyInto(packet, 16)
        writeShort(packet, 10, ipChecksum(packet, 0, IPV4_HEADER_LEN))

        writeUdpHeader(packet, IPV4_HEADER_LEN, request.destPort, request.sourcePort, udpLen, 0)
        System.arraycopy(dnsResponse, 0, packet, IPV4_HEADER_LEN + UDP_HEADER_LEN, dnsResponse.size)
        return packet
    }

    private fun buildIpv6Response(request: DnsPacketInfo, dnsResponse: ByteArray): ByteArray {
        val udpLen = UDP_HEADER_LEN + dnsResponse.size
        val packet = ByteArray(IPV6_HEADER_LEN + udpLen)

        // Version=6, Traffic Class=0, Flow Label=0
        packet[0] = 0x60
        packet[1] = 0
        packet[2] = 0
        packet[3] = 0
        writeShort(packet, 4, udpLen)
        packet[6] = IP_PROTOCOL_UDP.toByte()
        packet[7] = 64
        request.destIp.address?.copyInto(packet, 8)
        request.sourceIp.address?.copyInto(packet, 24)

        val udpOffset = IPV6_HEADER_LEN
        writeUdpHeader(packet, udpOffset, request.destPort, request.sourcePort, udpLen, 0)
        System.arraycopy(dnsResponse, 0, packet, udpOffset + UDP_HEADER_LEN, dnsResponse.size)
        val udpChecksum = computeUdpChecksumV6(
            packet,
            request.destIp.address,
            request.sourceIp.address,
            udpLen
        )
        writeShort(packet, udpOffset + 6, udpChecksum)
        return packet
    }

    private fun writeUdpHeader(
        packet: ByteArray,
        offset: Int,
        sourcePort: Int,
        destPort: Int,
        length: Int,
        checksum: Int
    ) {
        writeShort(packet, offset, sourcePort)
        writeShort(packet, offset + 2, destPort)
        writeShort(packet, offset + 4, length)
        writeShort(packet, offset + 6, checksum)
    }

    /**
     * 计算 IPv6 UDP checksum，覆盖 IPv6 伪头部 + UDP 头部 + payload。
     */
    private fun computeUdpChecksumV6(
        packet: ByteArray,
        sourceIp: ByteArray?,
        destIp: ByteArray?,
        udpLen: Int
    ): Int {
        if (sourceIp == null || destIp == null) return 0

        var sum = 0L
        sum = addChecksumBytes(sum, sourceIp, 0, sourceIp.size)
        sum = addChecksumBytes(sum, destIp, 0, destIp.size)
        sum += (udpLen ushr 16) and 0xFFFF
        sum += udpLen and 0xFFFF
        sum += IP_PROTOCOL_UDP
        sum = addChecksumBytes(sum, packet, IPV6_HEADER_LEN, udpLen)

        while (sum shr 16 != 0L) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return (sum.inv() and 0xFFFF).toInt()
    }

    private fun addChecksumBytes(sumStart: Long, data: ByteArray, offset: Int, length: Int): Long {
        var sum = sumStart
        var i = offset
        val end = offset + length
        while (i + 1 < end) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) {
            sum += (data[i].toInt() and 0xFF) shl 8
        }
        return sum
    }

    private fun readShort(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 8) or (buf[offset + 1].toInt() and 0xFF)
    }

    private fun writeShort(buf: ByteArray, offset: Int, value: Int) {
        buf[offset] = (value shr 8).toByte()
        buf[offset + 1] = value.toByte()
    }

    private fun ipChecksum(buf: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        val end = offset + length
        while (i < end) {
            sum += ((buf[i].toInt() and 0xFF) shl 8) or (buf[i + 1].toInt() and 0xFF)
            i += 2
        }
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv() and 0xFFFF
    }
}
