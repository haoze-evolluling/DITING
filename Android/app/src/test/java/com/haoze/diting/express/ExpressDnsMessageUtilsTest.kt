package com.haoze.diting.express

import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.vpn.BlockResponseMode
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class ExpressDnsMessageUtilsTest {

    @Test
    fun testBuildAndExtractQuestion() {
        val query = ExpressDnsMessageUtils.buildQuery("example.com", ExpressDnsMessageUtils.TYPE_A, 0x1234)
        val question = ExpressDnsMessageUtils.extractQuestion(query)
        assertNotNull(question)
        assertEquals("example.com", question!!.name)
        assertEquals(ExpressDnsMessageUtils.TYPE_A, question.type)
        assertEquals(1, question.qclass)
        assertEquals(0x1234, ExpressDnsMessageUtils.transactionId(query))
    }

    @Test
    fun testBlockedResponses() {
        val query = ExpressDnsMessageUtils.buildQuery("ad.block.me", ExpressDnsMessageUtils.TYPE_A, 0x5678)

        // NXDOMAIN
        val nxResp = ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.NXDOMAIN)
        assertEquals(ExpressDnsMessageUtils.RCODE_NXDOMAIN, ExpressDnsMessageUtils.responseCode(nxResp))
        assertEquals(0x5678, ExpressDnsMessageUtils.transactionId(nxResp))

        // REFUSED
        val refResp = ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.REFUSED)
        assertEquals(ExpressDnsMessageUtils.RCODE_REFUSED, ExpressDnsMessageUtils.responseCode(refResp))

        // ZERO_ADDRESS
        val zeroResp = ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
        assertEquals(ExpressDnsMessageUtils.RCODE_NOERROR, ExpressDnsMessageUtils.responseCode(zeroResp))
        val addrs = ExpressDnsMessageUtils.extractAddressRecords(zeroResp)
        assertEquals(1, addrs.size)
        assertEquals(InetAddress.getByName("0.0.0.0"), addrs[0])
    }

    @Test
    fun testEnsureEdns0() {
        val queryWithoutOpt = ExpressDnsMessageUtils.buildQuery("test.org", ExpressDnsMessageUtils.TYPE_A)
        assertFalse(ExpressDnsMessageUtils.hasOptRecord(queryWithoutOpt))

        val ednsQuery = ExpressDnsMessageUtils.ensureEdns0(queryWithoutOpt, 1232)
        assertTrue(ExpressDnsMessageUtils.hasOptRecord(ednsQuery))
        assertEquals(queryWithoutOpt.size + 11, ednsQuery.size)

        // Idempotent: ensuring again should not add another OPT
        val twice = ExpressDnsMessageUtils.ensureEdns0(ednsQuery, 1232)
        assertArrayEquals(ednsQuery, twice)
    }

    @Test
    fun testTtlPatching() {
        val query = ExpressDnsMessageUtils.buildQuery("zero.example", ExpressDnsMessageUtils.TYPE_A)
        val resp = ExpressDnsMessageUtils.buildBlockedResponse(query, BlockResponseMode.ZERO_ADDRESS)
        val initialTtl = ExpressDnsMessageUtils.cacheLifetimeSeconds(resp)
        assertEquals(300L, initialTtl)

        val patched = ExpressDnsMessageUtils.patchResponseTtl(resp, 50)
        assertNotNull(patched)
        assertEquals(250L, ExpressDnsMessageUtils.cacheLifetimeSeconds(patched!!))

        // Expired
        val expired = ExpressDnsMessageUtils.patchResponseTtl(resp, 300)
        assertNull(expired)
    }
}
