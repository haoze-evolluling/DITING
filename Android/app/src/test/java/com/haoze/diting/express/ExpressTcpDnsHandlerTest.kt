package com.haoze.diting.express

import com.haoze.diting.express.engine.ExpressDnsEngine
import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.express.engine.ExpressPacketCodec
import com.haoze.diting.express.engine.ExpressTcpDnsHandler
import com.haoze.diting.express.engine.ExpressUpstreamDispatcher
import com.haoze.diting.core.rule.BlockResponseMode
import com.haoze.diting.core.dns.DnsProtocol
import com.haoze.diting.core.dns.DnsProvider
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressTcpDnsHandlerTest {

    private val clientIp = byteArrayOf(10, 0, 0, 2)
    private val serverIp = byteArrayOf(10, 0, 0, 1)
    private val clientPort = 55555
    private val serverPort = 53

    private val provider = DnsProvider(id = "p", name = "Local", protocol = DnsProtocol.DNS, host = "10.0.0.1", port = 53)

    private fun createTestEngine(): ExpressDnsEngine {
        val dispatcher = ExpressUpstreamDispatcher(
            transportInvoker = { _, query, _, _ ->
                ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
            }
        )
        return ExpressDnsEngine(
            upstreamDispatcher = dispatcher,
            activeProvidersProvider = { listOf(provider) }
        )
    }

    @Test
    fun testTcpThreeWayHandshakeAndDnsQueryResponse() = runBlocking {
        val engine = createTestEngine()
        val handler = ExpressTcpDnsHandler(engine, mss = 1300)

        // 1. Client sends SYN
        val synPacket = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = serverIp,
            srcPort = clientPort,
            dstPort = serverPort,
            seqNumber = 1000L,
            ackNumber = 0L,
            flags = 0x02, // SYN
            window = 65535,
            payload = ByteArray(0)
        )

        val synAckList = handler.handlePacket(synPacket)
        assertEquals(1, synAckList.size)
        val synAck = synAckList[0]

        // Parse SYN-ACK
        val parsedSynAck = ExpressPacketCodec.parse(synAck)
        assertTrue(parsedSynAck is ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket)
        val synAckDetails = parsedSynAck as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x12, synAckDetails.flags) // SYN | ACK
        assertEquals(1001L, synAckDetails.ackNumber)
        val serverSeq = synAckDetails.seqNumber

        // 2. Client sends ACK + framed DNS query
        val rawDnsQuery = ExpressDnsMessageUtils.buildQuery("tcp.test", ExpressDnsMessageUtils.TYPE_A, 0x3333)
        val framedQuery = ByteArray(2 + rawDnsQuery.size)
        framedQuery[0] = (rawDnsQuery.size ushr 8).toByte()
        framedQuery[1] = (rawDnsQuery.size and 0xFF).toByte()
        System.arraycopy(rawDnsQuery, 0, framedQuery, 2, rawDnsQuery.size)

        val dataPacket = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = serverIp,
            srcPort = clientPort,
            dstPort = serverPort,
            seqNumber = 1001L,
            ackNumber = serverSeq + 1,
            flags = 0x18, // PSH | ACK
            window = 65535,
            payload = framedQuery
        )

        val responseList = handler.handlePacket(dataPacket)
        assertEquals(1, responseList.size)
        val respPacket = responseList[0]

        // Parse TCP response
        val parsedResp = ExpressPacketCodec.parse(respPacket)
        assertTrue(parsedResp is ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket)
        val respDetails = parsedResp as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x18, respDetails.flags) // PSH | ACK
        assertEquals(1001L + framedQuery.size, respDetails.ackNumber)

        // Verify framed DNS payload
        val tcpHeaderLen = 20
        val ipHeaderLen = 20
        val l4Payload = respPacket.copyOfRange(ipHeaderLen + tcpHeaderLen, respPacket.size)
        assertTrue(l4Payload.size >= 2)
        val dnsRespLen = ((l4Payload[0].toInt() and 0xFF) shl 8) or (l4Payload[1].toInt() and 0xFF)
        assertEquals(l4Payload.size - 2, dnsRespLen)
        val dnsRespBytes = l4Payload.copyOfRange(2, l4Payload.size)
        assertEquals(0x3333, ExpressDnsMessageUtils.transactionId(dnsRespBytes))
        assertEquals(ExpressDnsMessageUtils.RCODE_NOERROR, ExpressDnsMessageUtils.responseCode(dnsRespBytes))

        // 3. Client sends FIN
        val finPacket = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = serverIp,
            srcPort = clientPort,
            dstPort = serverPort,
            seqNumber = 1001L + framedQuery.size,
            ackNumber = synAckDetails.seqNumber + 1 + l4Payload.size,
            flags = 0x01, // FIN
            window = 65535,
            payload = ByteArray(0)
        )

        val finAckList = handler.handlePacket(finPacket)
        assertEquals(1, finAckList.size)
        val parsedFinAck = ExpressPacketCodec.parse(finAckList[0]) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x11, parsedFinAck.flags) // FIN | ACK
    }

    @Test
    fun testRstTerminatesConnection() = runBlocking {
        val engine = createTestEngine()
        val handler = ExpressTcpDnsHandler(engine)

        // SYN
        val synPacket = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = serverIp,
            srcPort = clientPort,
            dstPort = serverPort,
            seqNumber = 2000L,
            ackNumber = 0L,
            flags = 0x02,
            window = 65535,
            payload = ByteArray(0)
        )
        handler.handlePacket(synPacket)

        // RST
        val rstPacket = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = serverIp,
            srcPort = clientPort,
            dstPort = serverPort,
            seqNumber = 2001L,
            ackNumber = 0L,
            flags = 0x04,
            window = 65535,
            payload = ByteArray(0)
        )
        val resp = handler.handlePacket(rstPacket)
        assertTrue(resp.isEmpty())
    }

    @Test
    fun testPacketForNonExistentConnectionReturnsRst() = runBlocking {
        val engine = createTestEngine()
        val handler = ExpressTcpDnsHandler(engine)

        // Incoming ACK packet for unknown connection
        val orphanAck = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false,
            srcIp = clientIp,
            dstIp = serverIp,
            srcPort = clientPort,
            dstPort = serverPort,
            seqNumber = 12345L,
            ackNumber = 67890L,
            flags = 0x10, // ACK
            window = 65535,
            payload = ByteArray(0)
        )

        val responses = handler.handlePacket(orphanAck)
        assertEquals(1, responses.size)
        val rstPacket = responses[0]
        val parsed = ExpressPacketCodec.parse(rstPacket) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x04, parsed.flags) // RST
        assertEquals(67890L, parsed.seqNumber)
    }

    @Test
    fun testDuplicatePayloadDoesNotCorruptBuffer() = runBlocking {
        val engine = createTestEngine()
        val handler = ExpressTcpDnsHandler(engine)

        // 1. Handshake SYN
        val syn = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false, srcIp = clientIp, dstIp = serverIp,
            srcPort = clientPort, dstPort = serverPort,
            seqNumber = 1000L, ackNumber = 0L, flags = 0x02, window = 65535, payload = ByteArray(0)
        )
        val synAck = handler.handlePacket(syn)[0]
        val serverSeq = (ExpressPacketCodec.parse(synAck) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket).seqNumber

        // 2. Client sends query
        val query = ExpressDnsMessageUtils.buildQuery("dup.test", ExpressDnsMessageUtils.TYPE_A, 0x5555)
        val framed = ByteArray(2 + query.size).apply {
            this[0] = (query.size ushr 8).toByte()
            this[1] = (query.size and 0xFF).toByte()
            System.arraycopy(query, 0, this, 2, query.size)
        }
        val dataPacket = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false, srcIp = clientIp, dstIp = serverIp,
            srcPort = clientPort, dstPort = serverPort,
            seqNumber = 1001L, ackNumber = serverSeq + 1, flags = 0x18, window = 65535, payload = framed
        )
        val resp1 = handler.handlePacket(dataPacket)
        assertEquals(1, resp1.size) // DNS answer returned

        // 3. Client retransmits identical packet (duplicate)
        val resp2 = handler.handlePacket(dataPacket)
        assertEquals(1, resp2.size)
        val ackOnly = ExpressPacketCodec.parse(resp2[0]) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x10, ackOnly.flags) // Immediate ACK, not re-executing query
        assertEquals(1001L + framed.size, ackOnly.ackNumber)
    }

    @Test
    fun testFinWithPayloadProcessesPayloadAndAcksFin() = runBlocking {
        val engine = createTestEngine()
        val handler = ExpressTcpDnsHandler(engine)

        // Handshake SYN
        val syn = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false, srcIp = clientIp, dstIp = serverIp,
            srcPort = clientPort, dstPort = serverPort,
            seqNumber = 5000L, ackNumber = 0L, flags = 0x02, window = 65535, payload = ByteArray(0)
        )
        val synAck = handler.handlePacket(syn)[0]
        val serverSeq = (ExpressPacketCodec.parse(synAck) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket).seqNumber

        // Client sends query with PSH | ACK | FIN (0x19)
        val query = ExpressDnsMessageUtils.buildQuery("fin.test", ExpressDnsMessageUtils.TYPE_A, 0x6666)
        val framed = ByteArray(2 + query.size).apply {
            this[0] = (query.size ushr 8).toByte()
            this[1] = (query.size and 0xFF).toByte()
            System.arraycopy(query, 0, this, 2, query.size)
        }
        val dataWithFin = ExpressPacketCodec.ParsedPacket.DnsTcpPacket(
            isIpv6 = false, srcIp = clientIp, dstIp = serverIp,
            srcPort = clientPort, dstPort = serverPort,
            seqNumber = 5001L, ackNumber = serverSeq + 1, flags = 0x19, window = 65535, payload = framed
        )

        val responses = handler.handlePacket(dataWithFin)
        // Should contain DNS data response AND FIN-ACK
        assertEquals(2, responses.size)
        val dnsResp = ExpressPacketCodec.parse(responses[0]) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x18, dnsResp.flags) // PSH | ACK for data
        val finAck = ExpressPacketCodec.parse(responses[1]) as ExpressPacketCodec.ParsedPacket.NonDnsTcpPacket
        assertEquals(0x11, finAck.flags) // FIN | ACK
    }
}
