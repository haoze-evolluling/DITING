package com.haoze.diting.vpn

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DnsMessageUtilsTest {

    @Test
    fun nxdomainAndNodataResponses() {
        val queryA = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_A, 0x1234)
        val nxdomain = DnsMessageUtils.buildBlockedResponse(queryA, BlockResponseMode.NXDOMAIN)

        assertEquals(0x1234, DnsMessageUtils.transactionId(nxdomain))
        assertEquals(3, DnsMessageUtils.responseCode(nxdomain))

        val queryTxt = DnsMessageUtils.buildQuery("blocked.example", 16, 0x1235)
        val nodata = DnsMessageUtils.buildBlockedResponse(queryTxt, BlockResponseMode.NODATA)

        assertEquals(0x1235, DnsMessageUtils.transactionId(nodata))
        assertEquals(0, DnsMessageUtils.responseCode(nodata))
        assertEquals(300L, DnsMessageUtils.cacheLifetimeSeconds(nodata))
    }

    @Test
    fun zeroAddressResponses() {
        val queryA = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_A, 0x2001)
        val respA = DnsMessageUtils.buildBlockedResponse(queryA, BlockResponseMode.ZERO_ADDRESS)
        assertEquals(0, DnsMessageUtils.responseCode(respA))
        assertEquals("0.0.0.0", DnsMessageUtils.extractAddressRecords(respA).single().hostAddress)

        val queryAaaa = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_AAAA, 0x2002)
        val respAaaa = DnsMessageUtils.buildBlockedResponse(queryAaaa, BlockResponseMode.ZERO_ADDRESS)
        assertEquals(0, DnsMessageUtils.responseCode(respAaaa))
        assertTrue(DnsMessageUtils.extractAddressRecords(respAaaa).single().address.all { it == 0.toByte() })
    }

    @Test
    fun refusedAndMalformedResponses() {
        val query = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_A, 0x1236)
        val refused = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.REFUSED)
        assertEquals(0x1236, DnsMessageUtils.transactionId(refused))
        assertEquals(5, DnsMessageUtils.responseCode(refused))

        val malformedQuery = byteArrayOf(0x12, 0x34)
        val servfail = DnsMessageUtils.buildBlockedResponse(malformedQuery, BlockResponseMode.NXDOMAIN)
        assertEquals(0x1234, DnsMessageUtils.transactionId(servfail))
        assertEquals(2, DnsMessageUtils.responseCode(servfail))
    }

    @Test
    fun detectsTruncatedDnsResponse() {
        val response = byteArrayOf(0x12, 0x34, 0x82.toByte(), 0x00) + ByteArray(8)
        assertTrue(DnsMessageUtils.isTruncatedResponse(response))
    }

    @Test
    fun rewriteResponsesAnswerIpAndCnameTargets() {
        val queryA = DnsMessageUtils.buildQuery("hosts.example", DnsMessageUtils.TYPE_A, 0x3001)
        val respA = DnsRewriteMessage.buildResponse(
            queryA,
            setOf(RewriteAnswer("IPv4", "1.2.3.4"))
        )
        assertEquals(0x3001, DnsMessageUtils.transactionId(respA!!))
        assertEquals(0, DnsMessageUtils.responseCode(respA))
        assertEquals("1.2.3.4", DnsMessageUtils.extractAddressRecords(respA).single().hostAddress)

        val queryAaaa = DnsMessageUtils.buildQuery("hosts.example", DnsMessageUtils.TYPE_AAAA, 0x3002)
        val respAaaa = DnsRewriteMessage.buildResponse(
            queryAaaa,
            setOf(RewriteAnswer("IPv6", "::1"))
        )
        val address = DnsMessageUtils.extractAddressRecords(respAaaa!!).single()
        assertTrue(address.address.size == 16)
        assertTrue(address.address.dropLast(1).all { it == 0.toByte() })
        assertEquals(1.toByte(), address.address.last())
    }

    @Test
    fun rewriteResponseReturnsNullWhenNoTargetFits() {
        // A query with only a CNAME target: no IP answer fits.
        val queryA = DnsMessageUtils.buildQuery("hosts.example", DnsMessageUtils.TYPE_A, 0x3003)
        assertEquals(
            null,
            DnsRewriteMessage.buildResponse(queryA, setOf(RewriteAnswer("CNAME", "alias.example")))
        )
        // Malformed query yields no rewrite response.
        assertEquals(
            null,
            DnsRewriteMessage.buildResponse(byteArrayOf(0x12, 0x34), setOf(RewriteAnswer("IPv4", "1.2.3.4")))
        )
        assertEquals(
            null,
            DnsRewriteMessage.buildResponse(queryA, emptySet())
        )
    }
}
