package com.haoze.dnssr.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdGuardRuleParserTest {

    @Test
    fun parseBlockRulesWithModifiers() {
        val standard = AdGuardRuleParser.parseLine("||example.com^")
        assertNotNull(standard)
        assertEquals("example.com", standard!!.pattern)
        assertFalse(standard.important)
        assertNull(standard.appScope)

        val appImportant = AdGuardRuleParser.parseLine("||ads.net^\$app=com.app1|com.app2,important")
        assertNotNull(appImportant)
        assertEquals("ads.net", appImportant!!.pattern)
        assertTrue(appImportant.important)
        assertEquals("com.app1|com.app2", appImportant.appScope)
        assertFalse(appImportant.appInverted)

        val inverted = AdGuardRuleParser.parseLine("||tracker.com^\$app=~com.android.chrome")
        assertNotNull(inverted)
        assertEquals("tracker.com", inverted!!.pattern)
        assertEquals("com.android.chrome", inverted.appScope)
        assertTrue(inverted.appInverted)

        val wildcard = AdGuardRuleParser.parseLine("||*-analytics.google.com^\$app=com.google.android.gms")
        assertNotNull(wildcard)
        assertEquals("*-analytics.google.com", wildcard!!.pattern)
        assertTrue(wildcard.isWildcard)
    }

    @Test
    fun parseAllowRulesWithModifiers() {
        val allow = AdGuardRuleParser.parseAllowLine("@@||*-analytics.google.com^\$app=com.google.android.gms,important")
        assertNotNull(allow)
        assertEquals("*-analytics.google.com", allow!!.pattern)
        assertTrue(allow.isWildcard)
        assertTrue(allow.important)
        assertEquals("com.google.android.gms", allow.appScope)
    }

    @Test
    fun parseIgnoresCommentsAndWhitespace() {
        assertNull(AdGuardRuleParser.parseLine("! comment"))
        assertNull(AdGuardRuleParser.parseLine("# comment"))
        assertNull(AdGuardRuleParser.parseLine("   "))
        assertNull(AdGuardRuleParser.parseAllowLine("! allow comment"))
    }

    @Test
    fun wildcardPatternMatching() {
        val allWc = AdGuardRuleParser.WildcardPattern("*")
        assertTrue(allWc.matches("example.com"))

        val prefixSuffixWc = AdGuardRuleParser.WildcardPattern("*-analytics.google.com")
        assertTrue(prefixSuffixWc.matches("app-analytics.google.com"))
        assertTrue(prefixSuffixWc.matches("sub.app-analytics.google.com"))
        assertFalse(prefixSuffixWc.matches("other.google.com"))
    }

    @Test
    fun parseDnsrewriteRules() {
        val ipv4Line = AdGuardRuleParser.parseCategorizedLine("||example.com^\$dnsrewrite=1.2.3.4")
        assertEquals(1, ipv4Line.rewriteRules.size)
        assertEquals("example.com", ipv4Line.rewriteRules[0].pattern)
        assertEquals(com.haoze.dnssr.data.entity.RewriteTargetType.IPV4, ipv4Line.rewriteRules[0].targetType)
        assertEquals("1.2.3.4", ipv4Line.rewriteRules[0].targetValue)

        val ipv6Line = AdGuardRuleParser.parseCategorizedLine("||ipv6.com^\$dnsrewrite=2001:db8::1")
        assertEquals(1, ipv6Line.rewriteRules.size)
        assertEquals("ipv6.com", ipv6Line.rewriteRules[0].pattern)
        assertEquals(com.haoze.dnssr.data.entity.RewriteTargetType.IPV6, ipv6Line.rewriteRules[0].targetType)
        assertEquals("2001:db8::1", ipv6Line.rewriteRules[0].targetValue)

        val cnameLine = AdGuardRuleParser.parseCategorizedLine("||cname.com^\$dnsrewrite=target.example.org")
        assertEquals(1, cnameLine.rewriteRules.size)
        assertEquals("cname.com", cnameLine.rewriteRules[0].pattern)
        assertEquals(com.haoze.dnssr.data.entity.RewriteTargetType.CNAME, cnameLine.rewriteRules[0].targetType)
        assertEquals("target.example.org", cnameLine.rewriteRules[0].targetValue)

        val blockNxdomain = AdGuardRuleParser.parseCategorizedLine("||blocked.com^\$dnsrewrite=NXDOMAIN")
        assertEquals(1, blockNxdomain.blockRules.size)
        assertEquals("blocked.com", blockNxdomain.blockRules[0].pattern)

        val blockZero = AdGuardRuleParser.parseCategorizedLine("||sinkhole.com^\$dnsrewrite=0.0.0.0")
        assertEquals(1, blockZero.blockRules.size)
        assertEquals("sinkhole.com", blockZero.blockRules[0].pattern)
    }

    @Test
    fun parseHostsLines() {
        val sinkhole = AdGuardRuleParser.parseCategorizedLine("0.0.0.0 ads.example.com tracker.example.com # ad hosts")
        assertEquals(2, sinkhole.blockRules.size)
        assertEquals("ads.example.com", sinkhole.blockRules[0].pattern)
        assertEquals("tracker.example.com", sinkhole.blockRules[1].pattern)
        assertEquals(0, sinkhole.rewriteRules.size)

        val realIp = AdGuardRuleParser.parseCategorizedLine("1.2.3.4 host1.example.com host2.example.com")
        assertEquals(0, realIp.blockRules.size)
        assertEquals(2, realIp.rewriteRules.size)
        assertEquals("host1.example.com", realIp.rewriteRules[0].pattern)
        assertEquals("1.2.3.4", realIp.rewriteRules[0].targetValue)
        assertEquals("host2.example.com", realIp.rewriteRules[1].pattern)
        assertEquals("1.2.3.4", realIp.rewriteRules[1].targetValue)
    }

    @Test
    fun parseDnsmasqLines() {
        val block1 = AdGuardRuleParser.parseCategorizedLine("address=/blocked.com/")
        assertEquals(1, block1.blockRules.size)
        assertEquals("blocked.com", block1.blockRules[0].pattern)

        val block2 = AdGuardRuleParser.parseCategorizedLine("address=/sink.com/0.0.0.0")
        assertEquals(1, block2.blockRules.size)
        assertEquals("sink.com", block2.blockRules[0].pattern)

        val block3 = AdGuardRuleParser.parseCategorizedLine("address=/null.com/#")
        assertEquals(1, block3.blockRules.size)
        assertEquals("null.com", block3.blockRules[0].pattern)

        val rewriteIp = AdGuardRuleParser.parseCategorizedLine("address=/custom.com/10.0.0.1")
        assertEquals(1, rewriteIp.rewriteRules.size)
        assertEquals("custom.com", rewriteIp.rewriteRules[0].pattern)
        assertEquals("10.0.0.1", rewriteIp.rewriteRules[0].targetValue)
    }

    @Test
    fun parseCategorizedMixedText() {
        val text = """
            ! Title: Unified List
            # Comment line
            [Adblock Plus 2.0]
            example.com##.ad-banner
            ||ad.com^
            @@||allow.com^
            ||rewrite.com^${'$'}dnsrewrite=1.2.3.4
            0.0.0.0 sink.com
            10.0.0.2 real.com
            address=/masq-block.com/
            address=/masq-ip.com/10.0.0.3
        """.trimIndent()

        val categorized = AdGuardRuleParser.parseCategorized(text)
        assertEquals(3, categorized.blockRules.size) // ad.com, sink.com, masq-block.com
        assertEquals(1, categorized.allowRules.size) // allow.com
        assertEquals(3, categorized.rewriteRules.size) // rewrite.com -> 1.2.3.4, real.com -> 10.0.0.2, masq-ip.com -> 10.0.0.3
        assertEquals(4, categorized.ignoredCount) // 4 ignored lines: !..., #..., [...], example.com##...
    }
}
