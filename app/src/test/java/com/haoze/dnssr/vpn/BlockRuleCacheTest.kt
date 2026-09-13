package com.haoze.dnssr.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BlockRuleCacheTest {

    @Test
    fun findsTheMostSpecificMatchingRuleAndItsSource() {
        val cache = BlockRuleCache()
        cache.addPattern("example.com", "sub_8")
        cache.addPattern("ads.example.com", "sub_12")

        assertEquals(
            BlockRuleMatch(pattern = "ads.example.com", source = "sub_12"),
            cache.findMatch("tracker.ads.example.com")
        )
    }

    @Test
    fun returnsManualRuleSourceWithoutSubscriptionAttribution() {
        val cache = BlockRuleCache()
        cache.addPattern("example.com", "useradd")

        assertEquals("useradd", cache.findMatch("example.com")?.source)
        assertNull(cache.findMatch("unrelated.example.org"))
    }

    @Test
    fun matchesWildcardPattern() {
        val cache = BlockRuleCache()
        cache.addPattern("*-analytics.google.com", "useradd")

        assertEquals("useradd", cache.findMatch("app-analytics.google.com")?.source)
        assertEquals("useradd", cache.findMatch("sub.app-analytics.google.com")?.source)
        assertNull(cache.findMatch("other.google.com"))
    }
}
