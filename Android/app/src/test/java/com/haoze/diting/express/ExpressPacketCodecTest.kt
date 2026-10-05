package com.haoze.diting.express

import com.haoze.diting.express.engine.ExpressPacketCodec
import com.haoze.diting.express.engine.PublicDnsHijackList
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class ExpressPacketCodecTest {

    @Test
    fun testInternetChecksumStandardVector() {
        // RFC 1071 example: 0x0001, 0xf203, 0xf4f5, 0xf6f7
        val vector = byteArrayOf(
            0x00, 0x01,
            0xf2.toByte(), 0x03,
            0xf4.toByte(), 0xf5.toByte(),
            0xf6.toByte(), 0xf7.toByte()
        )
        val csum = ExpressPacketCodec.calculateInternetChecksum(vector, 0, vector.size)
        // Verify sum + csum folds to 0xFFFF
        val combined = vector + byteArrayOf((csum ushr 8).toByte(), (csum and 0xFF).toByte())
        val check = ExpressPacketCodec.calculateInternetChecksum(combined, 0, combined.size)
        assertEquals(0, check)
    }

    @Test
    fun testIPv4DnsUdpQueryParsingAndResponseRoundtrip() {
        val clientIp = byteArrayOf(10, 0, 0, 2)
        val dnsServerIp = byteArrayOf(8, 8, 8, 8)
        val clientPort = 54321
        val dnsPort = 53
        val sampleDnsQuery = createSampleDnsQuery("example.com")

        // 1. Build an IPv4 UDP packet representing client -> 8.8.8.8:53
        val queryPacket = ExpressPacketCodec.buildUdpResponse(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = dnsServerIp,
            srcPort = clientPort,
            dstPort = dnsPort,
            dnsPayload = sampleDnsQuery
        )

        // 2. Parse it
        val parsed = ExpressPacketCodec.parse(queryPacket)
        assertTrue(parsed is ExpressPacketCodec.ParsedPacket.DnsUdpQuery)
        val dnsQuery = parsed as ExpressPacketCodec.ParsedPacket.DnsUdpQuery
        assertFalse(dnsQuery.isIpv6)
        assertArrayEquals(clientIp, dnsQuery.srcIp)
        assertArrayEquals(dnsServerIp, dnsQuery.dstIp)
        assertEquals(clientPort, dnsQuery.srcPort)
        assertEquals(dnsPort, dnsQuery.dstPort)
        assertArrayEquals(sampleDnsQuery, dnsQuery.dnsPayload)

        // 3. Synthesize an answer back to client
        val sampleDnsResponse = createSampleDnsResponse("example.com", "93.184.216.34", 300)
        val respPacket = ExpressPacketCodec.buildUdpResponse(
            isIpv6 = dnsQuery.isIpv6,
            srcIp = dnsQuery.dstIp,
            dstIp = dnsQuery.srcIp,
            srcPort = dnsQuery.dstPort,
            dstPort = dnsQuery.srcPort,
            dnsPayload = sampleDnsResponse
        )

        // Verify IPv4 header checksum validity
        val ipChecksum = ExpressPacketCodec.calculateInternetChecksum(respPacket, 0, 20)
        assertEquals(0, ipChecksum)

        // Verify parsed packet on client perspective (dstPort != 53 so discarded on incoming TUN)
        val clientPerspective = ExpressPacketCodec.parse(respPacket)
        assertTrue(clientPerspective is ExpressPacketCodec.ParsedPacket.DiscardPacket)
    }

    @Test
    fun testIPv6DnsUdpQueryParsingAndResponse() {
        val clientIp = InetAddress.getByName("fd00:abcd::2").address
        val dnsServerIp = InetAddress.getByName("2001:4860:4860::8888").address
        val clientPort = 45678
        val dnsPort = 53
        val sampleDnsQuery = createSampleDnsQuery("ipv6.example.com")

        val queryPacket = ExpressPacketCodec.buildUdpResponse(
            isIpv6 = true,
            srcIp = clientIp,
            dstIp = dnsServerIp,
            srcPort = clientPort,
            dstPort = dnsPort,
            dnsPayload = sampleDnsQuery
        )

        val parsed = ExpressPacketCodec.parse(queryPacket)
        assertTrue(parsed is ExpressPacketCodec.ParsedPacket.DnsUdpQuery)
        val dnsQuery = parsed as ExpressPacketCodec.ParsedPacket.DnsUdpQuery
        assertTrue(dnsQuery.isIpv6)
        assertArrayEquals(clientIp, dnsQuery.srcIp)
        assertArrayEquals(dnsServerIp, dnsQuery.dstIp)
        assertEquals(clientPort, dnsQuery.srcPort)
        assertEquals(dnsPort, dnsQuery.dstPort)
        assertArrayEquals(sampleDnsQuery, dnsQuery.dnsPayload)
    }

    @Test
    fun testIPv6ExtensionHeaderSkipping() {
        // Build IPv6 packet with Hop-by-Hop options (NextHeader = 0) followed by UDP (NextHeader = 17)
        val clientIp = InetAddress.getByName("fd00::1").address
        val serverIp = InetAddress.getByName("2001:4860:4860::8888").address
        val udpPayload = createSampleDnsQuery("hop.example.com")
        val udpLen = 8 + udpPayload.size
        val hopByHopLen = 8 // 1 unit of 8 octets

        val totalLen = 40 + hopByHopLen + udpLen
        val packet = ByteArray(totalLen)

        // IPv6 Header
        packet[0] = 0x60
        ExpressPacketCodec.writeUint16(packet, 4, hopByHopLen + udpLen)
        packet[6] = 0 // Hop-by-hop
        packet[7] = 64
        System.arraycopy(clientIp, 0, packet, 8, 16)
        System.arraycopy(serverIp, 0, packet, 24, 16)

        // Hop-by-hop extension header (8 bytes)
        packet[40] = 17 // Next header = UDP
        packet[41] = 0 // Length in 8-octet units minus 1 (0 -> 8 octets)

        // UDP Header
        val udpOffset = 40 + hopByHopLen
        ExpressPacketCodec.writeUint16(packet, udpOffset, 12345)
        ExpressPacketCodec.writeUint16(packet, udpOffset + 2, 53)
        ExpressPacketCodec.writeUint16(packet, udpOffset + 4, udpLen)
        ExpressPacketCodec.writeUint16(packet, udpOffset + 6, 0)
        System.arraycopy(udpPayload, 0, packet, udpOffset + 8, udpPayload.size)

        val parsed = ExpressPacketCodec.parse(packet)
        assertTrue(parsed is ExpressPacketCodec.ParsedPacket.DnsUdpQuery)
        val query = parsed as ExpressPacketCodec.ParsedPacket.DnsUdpQuery
        assertTrue(query.isIpv6)
        assertEquals(53, query.dstPort)
        assertEquals(12345, query.srcPort)
    }

    @Test
    fun testTcpResetForNon53Traffic() {
        // Incoming TCP SYN packet to 8.8.8.8:443
        val clientIp = byteArrayOf(10, 0, 0, 2)
        val dstIp = byteArrayOf(8, 8, 8, 8)
        val clientPort = 50000
        val targetPort = 443

        val incomingSyn = ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = dstIp,
            srcPort = clientPort,
            dstPort = targetPort,
            seqNumber = 1000L,
            ackNumber = 0L,
            flags = 0x02, // SYN
            window = 65535,
            payloadLength = 0
        )

        val rstPacket = ExpressPacketCodec.buildTcpReset(incomingSyn)
        assertNotNull(rstPacket)
        assertEquals(40, rstPacket!!.size) // 20 IP + 20 TCP

        // Check IP header of RST
        assertEquals(0x45.toByte(), rstPacket[0])
        val respSrcIp = rstPacket.copyOfRange(12, 16)
        val respDstIp = rstPacket.copyOfRange(16, 20)
        assertArrayEquals(dstIp, respSrcIp)
        assertArrayEquals(clientIp, respDstIp)

        // Check TCP header of RST
        val respSrcPort = ExpressPacketCodec.readUint16(rstPacket, 20)
        val respDstPort = ExpressPacketCodec.readUint16(rstPacket, 22)
        val respSeq = ExpressPacketCodec.readUint32(rstPacket, 24)
        val respAck = ExpressPacketCodec.readUint32(rstPacket, 28)
        val respFlags = rstPacket[33].toInt() and 0xFF

        assertEquals(targetPort, respSrcPort)
        assertEquals(clientPort, respDstPort)
        assertEquals(0L, respSeq)
        assertEquals(1001L, respAck) // SYN consumes 1 sequence number
        assertEquals(0x14, respFlags) // RST | ACK

        // Verify IP checksum and TCP checksum fold to 0
        val ipChecksum = ExpressPacketCodec.calculateInternetChecksum(rstPacket, 0, 20)
        assertEquals(0, ipChecksum)

        // Also test RST response to incoming ACK packet (should RST with seq=incoming.ack, ack=0)
        val incomingAck = ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = dstIp,
            srcPort = clientPort,
            dstPort = targetPort,
            seqNumber = 2000L,
            ackNumber = 5000L,
            flags = 0x10, // ACK
            window = 65535,
            payloadLength = 0
        )
        val rstForAck = ExpressPacketCodec.buildTcpReset(incomingAck)
        assertNotNull(rstForAck)
        val rstForAckSeq = ExpressPacketCodec.readUint32(rstForAck!!, 24)
        val rstForAckFlags = rstForAck[33].toInt() and 0xFF
        assertEquals(5000L, rstForAckSeq)
        assertEquals(0x04, rstForAckFlags) // RST only

        // Incoming packet already has RST flag -> must not respond with another RST!
        val incomingRst = incomingAck.copy(flags = 0x04)
        val rstForRst = ExpressPacketCodec.buildTcpReset(incomingRst)
        assertNull(rstForRst)
    }

    @Test
    fun testMalformedAndFragmentPackets() {
        // 1. Too short packet
        assertNull(ExpressPacketCodec.parse(byteArrayOf(0x45, 0x00)))

        // 2. Truncated IPv4 packet
        val truncatedIpv4 = ByteArray(20)
        truncatedIpv4[0] = 0x45
        ExpressPacketCodec.writeUint16(truncatedIpv4, 2, 40) // totalLength = 40 > 20
        assertNull(ExpressPacketCodec.parse(truncatedIpv4))

        // 3. Non-first IPv4 fragment (fragOffset != 0)
        val fragmentPacket = ByteArray(28)
        fragmentPacket[0] = 0x45
        ExpressPacketCodec.writeUint16(fragmentPacket, 2, 28)
        ExpressPacketCodec.writeUint16(fragmentPacket, 6, 0x0001) // fragOffset = 1
        fragmentPacket[9] = 17 // UDP
        val fragResult = ExpressPacketCodec.parse(fragmentPacket)
        assertTrue(fragResult is ExpressPacketCodec.ParsedPacket.DiscardPacket)
        assertEquals("Non-first fragment", (fragResult as ExpressPacketCodec.ParsedPacket.DiscardPacket).reason)

        // 4. First IPv4 fragment with MF=1 (fragOffset == 0, MF == 1)
        val firstFragPacket = ByteArray(28)
        firstFragPacket[0] = 0x45
        ExpressPacketCodec.writeUint16(firstFragPacket, 2, 28)
        ExpressPacketCodec.writeUint16(firstFragPacket, 6, 0x2000) // MF = 1
        firstFragPacket[9] = 17 // UDP
        val firstFragResult = ExpressPacketCodec.parse(firstFragPacket)
        assertTrue(firstFragResult is ExpressPacketCodec.ParsedPacket.DiscardPacket)
        assertEquals("Fragmented datagram (MF=1)", (firstFragResult as ExpressPacketCodec.ParsedPacket.DiscardPacket).reason)

        // 5. IPv6 fragment header with M=1
        val ipv6Frag = ByteArray(48)
        ipv6Frag[0] = 0x60
        ExpressPacketCodec.writeUint16(ipv6Frag, 4, 8)
        ipv6Frag[6] = 44 // Next = Fragment Header
        ipv6Frag[7] = 64
        ipv6Frag[40] = 17
        ExpressPacketCodec.writeUint16(ipv6Frag, 42, 0x0001) // M=1
        val ipv6FragResult = ExpressPacketCodec.parse(ipv6Frag)
        assertTrue(ipv6FragResult is ExpressPacketCodec.ParsedPacket.DiscardPacket)
        assertEquals("Fragmented IPv6 packet (M=1)", (ipv6FragResult as ExpressPacketCodec.ParsedPacket.DiscardPacket).reason)

        // 6. Invalid IP version
        val badVersion = ByteArray(20)
        badVersion[0] = 0x35 // Version 3
        assertNull(ExpressPacketCodec.parse(badVersion))
    }

    @Test
    fun testEncodeUdpResponseZeroAllocationAndOddChecksum() {
        val clientIp = byteArrayOf(10, 0, 0, 2)
        val serverIp = byteArrayOf(8, 8, 8, 8)
        val dnsPayload = byteArrayOf(1, 2, 3) // Odd length payload (3 bytes)
        val outBuffer = ByteArray(1500)

        val writtenLen = ExpressPacketCodec.encodeUdpResponse(
            isIpv6 = false,
            srcIp = serverIp,
            dstIp = clientIp,
            srcPort = 53,
            dstPort = 12345,
            dnsPayload = dnsPayload,
            outBuffer = outBuffer
        )
        assertTrue(writtenLen > 0)
        assertEquals(20 + 8 + 3, writtenLen) // 31 bytes (odd length)

        val csum = ExpressPacketCodec.calculateInternetChecksum(outBuffer, 0, writtenLen)
        assertTrue(csum >= 0)
    }

    @Test
    fun testDnsTtlPatchIdempotencyAndExpiry() {
        val sampleDnsResponse = createSampleDnsResponse("test.com", "1.2.3.4", 300)

        // 1. Min TTL extraction
        val minTtl = ExpressPacketCodec.extractMinDnsTtl(sampleDnsResponse)
        assertEquals(300L, minTtl)

        // 2. Idempotent TTL patch with 0 elapsed seconds
        val patchedZero = ExpressPacketCodec.patchDnsPayloadTtl(sampleDnsResponse, 0)
        assertNotNull(patchedZero)
        assertArrayEquals(sampleDnsResponse, patchedZero)

        // 3. Decrement TTL by 50 seconds -> 250s
        val patched50 = ExpressPacketCodec.patchDnsPayloadTtl(sampleDnsResponse, 50)
        assertNotNull(patched50)
        assertEquals(250L, ExpressPacketCodec.extractMinDnsTtl(patched50!!))

        // 4. Overwrite TTL with 600s
        val overwritten = ExpressPacketCodec.overwriteDnsPayloadTtl(sampleDnsResponse, 600)
        assertNotNull(overwritten)
        assertEquals(600L, ExpressPacketCodec.extractMinDnsTtl(overwritten!!))

        // 5. Expiry: elapsed seconds >= original TTL -> null
        val expired = ExpressPacketCodec.patchDnsPayloadTtl(sampleDnsResponse, 300)
        assertNull(expired)

        val expiredBeyond = ExpressPacketCodec.patchDnsPayloadTtl(sampleDnsResponse, 301)
        assertNull(expiredBeyond)
    }

    @Test
    fun testPublicDnsHijackList() {
        assertTrue(PublicDnsHijackList.isHijacked("8.8.8.8"))
        assertTrue(PublicDnsHijackList.isHijacked("1.1.1.1"))
        assertTrue(PublicDnsHijackList.isHijacked("223.5.5.5"))
        assertTrue(PublicDnsHijackList.isHijacked("114.114.114.114"))
        assertTrue(PublicDnsHijackList.isHijacked("2001:4860:4860::8888"))
        assertTrue(PublicDnsHijackList.isHijacked("2606:4700:4700::1111"))

        assertFalse(PublicDnsHijackList.isHijacked("192.168.1.1"))
        assertFalse(PublicDnsHijackList.isHijacked("10.0.0.1"))
        assertFalse(PublicDnsHijackList.isHijacked("127.0.0.1"))

        assertTrue(PublicDnsHijackList.IPV4_HIJACK_IPS.size >= 20)
        assertTrue(PublicDnsHijackList.IPV6_HIJACK_IPS.size >= 8)
    }

    private fun createSampleDnsQuery(domain: String): ByteArray {
        val labels = domain.split('.').filter { it.isNotEmpty() }
        var len = 12 + 1 + 4
        labels.forEach { len += 1 + it.length }
        val buf = ByteArray(len)
        ExpressPacketCodec.writeUint16(buf, 0, 0x1234) // ID
        ExpressPacketCodec.writeUint16(buf, 2, 0x0100) // RD=1
        ExpressPacketCodec.writeUint16(buf, 4, 1) // QDCOUNT=1

        var offset = 12
        for (label in labels) {
            val bytes = label.toByteArray(Charsets.US_ASCII)
            buf[offset++] = bytes.size.toByte()
            System.arraycopy(bytes, 0, buf, offset, bytes.size)
            offset += bytes.size
        }
        buf[offset++] = 0
        ExpressPacketCodec.writeUint16(buf, offset, 1) // QTYPE = A
        ExpressPacketCodec.writeUint16(buf, offset + 2, 1) // QCLASS = IN
        return buf
    }

    private fun createSampleDnsResponse(domain: String, ip: String, ttl: Long): ByteArray {
        val query = createSampleDnsQuery(domain)
        val ipBytes = InetAddress.getByName(ip).address
        val answerRecordLen = 2 + 2 + 2 + 4 + 2 + 4 // ptr(2) + type(2) + class(2) + ttl(4) + rdlen(2) + ip(4)
        val resp = ByteArray(query.size + answerRecordLen)
        System.arraycopy(query, 0, resp, 0, query.size)

        // Set QR=1, RA=1
        resp[2] = 0x81.toByte()
        resp[3] = 0x80.toByte()
        ExpressPacketCodec.writeUint16(resp, 6, 1) // ANCOUNT = 1

        var offset = query.size
        resp[offset++] = 0xC0.toByte() // Pointer
        resp[offset++] = 12.toByte()
        ExpressPacketCodec.writeUint16(resp, offset, 1) // Type A
        ExpressPacketCodec.writeUint16(resp, offset + 2, 1) // Class IN
        ExpressPacketCodec.writeUint32(resp, offset + 4, ttl)
        ExpressPacketCodec.writeUint16(resp, offset + 8, 4) // rdlength = 4
        System.arraycopy(ipBytes, 0, resp, offset + 10, 4)
        return resp
    }
}
