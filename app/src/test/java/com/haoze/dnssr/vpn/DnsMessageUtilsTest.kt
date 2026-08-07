package com.haoze.dnssr.vpn

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DnsMessageUtilsTest {

    @Test
    fun nxdomainResponseIncludesNegativeCacheSoa() {
        val query = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_A, 0x1234)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.NXDOMAIN)

        assertEquals(0x1234, DnsMessageUtils.transactionId(response))
        assertEquals(3, DnsMessageUtils.responseCode(response))
        assertEquals(1, readShort(response, 4))
        assertEquals(0, readShort(response, 6))
        assertEquals(1, readShort(response, 8))
        assertEquals(0, readShort(response, 10))
        assertArrayEquals(query.copyOfRange(12, query.size), response.copyOfRange(12, query.size))

        val soaOffset = query.size
        assertEquals(6, readShort(response, soaOffset + 2))
        assertEquals(300L, readUnsignedInt(response, soaOffset + 6))
        assertEquals(22, readShort(response, soaOffset + 10))
        assertEquals(300L, readUnsignedInt(response, soaOffset + 30))
    }

    @Test
    fun nodataResponseIncludesNegativeCacheSoa() {
        val query = DnsMessageUtils.buildQuery("blocked.example", 16, 0x1235)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.NODATA)

        assertEquals(0x1235, DnsMessageUtils.transactionId(response))
        assertEquals(0, DnsMessageUtils.responseCode(response))
        assertEquals(1, readShort(response, 4))
        assertEquals(0, readShort(response, 6))
        assertEquals(1, readShort(response, 8))
        assertEquals(300L, DnsMessageUtils.cacheLifetimeSeconds(response))

        val soaOffset = query.size
        assertEquals(6, readShort(response, soaOffset + 2))
        assertEquals(300L, readUnsignedInt(response, soaOffset + 6))
        assertEquals(300L, readUnsignedInt(response, soaOffset + 30))
    }

    @Test
    fun refusedResponsePreservesQuestionWithoutRecords() {
        val query = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_A, 0x1236)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.REFUSED)

        assertEquals(0x1236, DnsMessageUtils.transactionId(response))
        assertEquals(5, DnsMessageUtils.responseCode(response))
        assertEquals(1, readShort(response, 4))
        assertEquals(0, readShort(response, 6))
        assertEquals(0, readShort(response, 8))
        assertEquals(0, readShort(response, 10))
        assertEquals(query.size, response.size)
        assertArrayEquals(query.copyOfRange(12, query.size), response.copyOfRange(12, response.size))
    }

    @Test
    fun unknownBlockResponseModeFallsBackToNxdomain() {
        assertEquals(BlockResponseMode.NXDOMAIN, BlockResponseMode.fromStorageValue("unknown"))
    }

    @Test
    fun zeroAddressModeReturnsIpv4Answer() {
        val query = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_A, 0x2001)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)

        assertEquals(0, DnsMessageUtils.responseCode(response))
        assertEquals(1, readShort(response, 6))
        assertEquals(0, readShort(response, 8))
        assertArrayEquals(ByteArray(4), response.copyOfRange(query.size + 12, query.size + 16))
        assertEquals("0.0.0.0", DnsMessageUtils.extractAddressRecords(response).single().hostAddress)
    }

    @Test
    fun zeroAddressModeReturnsIpv6Answer() {
        val query = DnsMessageUtils.buildQuery("blocked.example", DnsMessageUtils.TYPE_AAAA, 0x2002)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)

        assertEquals(0, DnsMessageUtils.responseCode(response))
        assertEquals(1, readShort(response, 6))
        assertArrayEquals(ByteArray(16), response.copyOfRange(query.size + 12, query.size + 28))
        assertTrue(DnsMessageUtils.extractAddressRecords(response).single().address.all { it == 0.toByte() })
    }

    @Test
    fun zeroAddressModeReturnsNegativeCachedEmptyAnswerForOtherTypes() {
        val query = DnsMessageUtils.buildQuery("blocked.example", 16, 0x2003)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)

        assertEquals(0, DnsMessageUtils.responseCode(response))
        assertEquals(0, readShort(response, 6))
        assertEquals(1, readShort(response, 8))
        assertEquals(300L, DnsMessageUtils.cacheLifetimeSeconds(response))
    }

    @Test
    fun malformedQueryFallsBackToServfail() {
        val query = byteArrayOf(0x12, 0x34)

        val response = DnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.NXDOMAIN)

        assertEquals(12, response.size)
        assertEquals(0x1234, DnsMessageUtils.transactionId(response))
        assertEquals(2, DnsMessageUtils.responseCode(response))
        assertEquals(0, readShort(response, 4))
    }

    @Test
    fun detectsTruncatedDnsResponse() {
        val response = byteArrayOf(0x12, 0x34, 0x82.toByte(), 0x00) + ByteArray(8)

        assertTrue(DnsMessageUtils.isTruncatedResponse(response))
    }

    private fun readShort(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 8) or
                (bytes[offset + 1].toInt() and 0xFF)
    }

    private fun readUnsignedInt(bytes: ByteArray, offset: Int): Long {
        return ((bytes[offset].toLong() and 0xFF) shl 24) or
                ((bytes[offset + 1].toLong() and 0xFF) shl 16) or
                ((bytes[offset + 2].toLong() and 0xFF) shl 8) or
                (bytes[offset + 3].toLong() and 0xFF)
    }
}
