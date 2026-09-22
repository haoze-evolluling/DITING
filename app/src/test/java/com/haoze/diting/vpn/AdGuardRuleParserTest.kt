package com.haoze.diting.vpn

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
        assertEquals(com.haoze.diting.data.entity.RewriteTargetType.IPV4, ipv4Line.rewriteRules[0].targetType)
        assertEquals("1.2.3.4", ipv4Line.rewriteRules[0].targetValue)

        val ipv6Line = AdGuardRuleParser.parseCategorizedLine("||ipv6.com^\$dnsrewrite=2001:db8::1")
        assertEquals(1, ipv6Line.rewriteRules.size)
        assertEquals("ipv6.com", ipv6Line.rewriteRules[0].pattern)
        assertEquals(com.haoze.diting.data.entity.RewriteTargetType.IPV6, ipv6Line.rewriteRules[0].targetType)
        assertEquals("2001:db8::1", ipv6Line.rewriteRules[0].targetValue)

        val cnameLine = AdGuardRuleParser.parseCategorizedLine("||cname.com^\$dnsrewrite=target.example.org")
        assertEquals(1, cnameLine.rewriteRules.size)
        assertEquals("cname.com", cnameLine.rewriteRules[0].pattern)
        assertEquals(com.haoze.diting.data.entity.RewriteTargetType.CNAME, cnameLine.rewriteRules[0].targetType)
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

    @Test
    fun parseAllModifier() {
        val rule = AdGuardRuleParser.parseLine("||example.com^\$all")
        assertNotNull(rule)
        assertEquals("example.com", rule!!.pattern)

        val impRule = AdGuardRuleParser.parseLine("||example.com^\$all,important")
        assertNotNull(impRule)
        assertEquals("example.com", impRule!!.pattern)
        assertTrue(impRule.important)
    }

    @Test
    fun parseNegativeAppPrefix() {
        val rule = AdGuardRuleParser.parseLine("||tracker.com^\$~app=com.android.chrome")
        assertNotNull(rule)
        assertEquals("tracker.com", rule!!.pattern)
        assertEquals("com.android.chrome", rule.appScope)
        assertTrue(rule.appInverted)
    }

    @Test
    fun parseBadfilterAndWebOnlyModifiers() {
        val badfilterLine = AdGuardRuleParser.parseCategorizedLine("||example.com/banner.js\$script,badfilter")
        assertEquals(1, badfilterLine.ignoredCount)
        assertEquals(0, badfilterLine.blockRules.size)

        val webOnlyLine = AdGuardRuleParser.parseCategorizedLine("||example.com^\$image,third-party")
        assertEquals(1, webOnlyLine.ignoredCount)
        assertEquals(0, webOnlyLine.blockRules.size)

        val removeparamLine = AdGuardRuleParser.parseCategorizedLine("||example.com^\$removeparam=utm_source")
        assertEquals(1, removeparamLine.ignoredCount)
        assertEquals(0, webOnlyLine.blockRules.size)
    }

    @Test
    fun badfilterDisablesTargetBlockRule() {
        val text = """
            ||example.com^
            ||example.com^${'$'}badfilter
        """.trimIndent()

        val categorized = AdGuardRuleParser.parseCategorized(text)
        assertEquals(0, categorized.blockRules.size)
        assertEquals(1, categorized.badfilteredCount)

        // Verify order independence: badfilter defined before the target rule
        val reversedText = """
            ||example.com^${'$'}badfilter
            ||example.com^
        """.trimIndent()
        val revCategorized = AdGuardRuleParser.parseCategorized(reversedText)
        assertEquals(0, revCategorized.blockRules.size)
        assertEquals(1, revCategorized.badfilteredCount)
    }

    @Test
    fun badfilterAllowOnlyDisablesAllowRule() {
        // White list badfilter only disables allow rule, not block rule
        val text = """
            ||example.com^
            @@||example.com^
            @@||example.com^${'$'}badfilter
        """.trimIndent()

        val categorized = AdGuardRuleParser.parseCategorized(text)
        assertEquals(1, categorized.blockRules.size)
        assertEquals("example.com", categorized.blockRules[0].pattern)
        assertEquals(0, categorized.allowRules.size)
        assertEquals(1, categorized.badfilteredCount)

        // Block badfilter only disables block rule, not allow rule
        val text2 = """
            ||example.com^
            @@||example.com^
            ||example.com^${'$'}badfilter
        """.trimIndent()
        val categorized2 = AdGuardRuleParser.parseCategorized(text2)
        assertEquals(0, categorized2.blockRules.size)
        assertEquals(1, categorized2.allowRules.size)
        assertEquals("example.com", categorized2.allowRules[0].pattern)
        assertEquals(1, categorized2.badfilteredCount)
    }

    @Test
    fun badfilterWildcardAndRewriteRules() {
        val text = """
            ||*-analytics.google.com^
            ||*-analytics.google.com^${'$'}badfilter
            ||rewrite.example.com^${'$'}dnsrewrite=1.2.3.4
            ||rewrite.example.com^${'$'}dnsrewrite=1.2.3.4,badfilter
            ||rewrite.keep.com^${'$'}dnsrewrite=1.2.3.4
            ||rewrite.keep.com^${'$'}dnsrewrite=5.6.7.8,badfilter
        """.trimIndent()

        val categorized = AdGuardRuleParser.parseCategorized(text)
        assertEquals(0, categorized.blockRules.size)
        assertEquals(1, categorized.rewriteRules.size)
        assertEquals("rewrite.keep.com", categorized.rewriteRules[0].pattern)
        assertEquals("1.2.3.4", categorized.rewriteRules[0].targetValue)
        assertEquals(2, categorized.badfilteredCount)
    }

    @Test
    fun nonMatchingBadfilterDoesNotAffectOtherRules() {
        val text = """
            ||ads.net^${'$'}important
            ||ads.net^${'$'}badfilter
            ||tracker.com^${'$'}app=com.app1
            ||tracker.com^${'$'}app=com.app2,badfilter
            ||unrelated.com^
            ||other.com^${'$'}badfilter
        """.trimIndent()

        val categorized = AdGuardRuleParser.parseCategorized(text)
        assertEquals(3, categorized.blockRules.size)
        assertEquals(0, categorized.badfilteredCount)

        // Matching important and appScope
        val matchingText = """
            ||ads.net^${'$'}important
            ||ads.net^${'$'}important,badfilter
            ||tracker.com^${'$'}app=com.app1
            ||tracker.com^${'$'}app=com.app1,badfilter
        """.trimIndent()
        val matchingCat = AdGuardRuleParser.parseCategorized(matchingText)
        assertEquals(0, matchingCat.blockRules.size)
        assertEquals(2, matchingCat.badfilteredCount)
    }

    @Test
    fun extractBadfilterKeysExtractsExpectedKeys() {
        val text = """
            ! comment with ${'$'}badfilter
            ||example.com^${'$'}badfilter
            @@||allow.com^${'$'}badfilter
            ||rewrite.com^${'$'}dnsrewrite=1.2.3.4,badfilter
            ||invalid...^${'$'}badfilter
            ||web.com/ads.js${'$'}script,badfilter
        """.trimIndent()

        val keys = AdGuardRuleParser.extractBadfilterKeys(text)
        assertEquals(
            setOf(
                "block:example.com:false:null:false",
                "allow:allow.com:false:null:false",
                "rewrite:rewrite.com:IPv4:1.2.3.4"
            ),
            keys
        )
    }

    @Test
    fun parseDenyallowModifier() {
        val line = "||example.com^\$denyallow=sub.example.com|test.example.com"
        val parsed = AdGuardRuleParser.parseCategorizedLine(line)
        assertEquals(1, parsed.blockRules.size)
        val rule = parsed.blockRules[0]
        assertEquals("example.com", rule.pattern)
        assertEquals("sub.example.com|test.example.com", rule.denyallow)

        val invalid = AdGuardRuleParser.parseCategorizedLine("||example.com^\$denyallow=")
        assertEquals(1, invalid.invalidCount)
    }

    @Test
    fun parseRegexRules() {
        val standardRegex = AdGuardRuleParser.parseCategorizedLine("/^ad.*\\.example\\.com$/")
        assertEquals(1, standardRegex.blockRules.size)
        val rule1 = standardRegex.blockRules[0]
        assertEquals("^ad.*\\.example\\.com$", rule1.pattern)
        assertTrue(rule1.isRegex)
        assertFalse(rule1.important)

        val regexWithModifiers = AdGuardRuleParser.parseCategorizedLine("/^tracker\\..*/\$important,app=com.example")
        assertEquals(1, regexWithModifiers.blockRules.size)
        val rule2 = regexWithModifiers.blockRules[0]
        assertEquals("^tracker\\..*", rule2.pattern)
        assertTrue(rule2.isRegex)
        assertTrue(rule2.important)
        assertEquals("com.example", rule2.appScope)

        val allowRegex = AdGuardRuleParser.parseCategorizedLine("@@/^allowed\\..*/")
        assertEquals(1, allowRegex.allowRules.size)
        val allowRule = allowRegex.allowRules[0]
        assertEquals("^allowed\\..*", allowRule.pattern)
        assertTrue(allowRule.isRegex)

        val invalidRegex = AdGuardRuleParser.parseCategorizedLine("/[a-z/")
        assertEquals(1, invalidRegex.invalidCount)
    }

    @Test
    fun parseDnstypeModifier() {
        val qtypeRule = AdGuardRuleParser.parseCategorizedLine("||example.com^\$dnstype=AAAA")
        assertEquals(1, qtypeRule.blockRules.size)
        assertEquals("AAAA", qtypeRule.blockRules[0].dnsType)

        val invertedType = AdGuardRuleParser.parseCategorizedLine("||example.com^\$dnstype=~A")
        assertEquals(1, invertedType.blockRules.size)
        assertEquals("~A", invertedType.blockRules[0].dnsType)

        val multiType = AdGuardRuleParser.parseCategorizedLine("||example.com^\$dnstype=A|AAAA")
        assertEquals(1, multiType.blockRules.size)
        assertEquals("A|AAAA", multiType.blockRules[0].dnsType)

        val invalidType = AdGuardRuleParser.parseCategorizedLine("||example.com^\$dnstype=INVALID_TYPE")
        assertEquals(1, invalidType.unsupportedCount)
    }

    @Test
    fun badfilterWithP1Modifiers() {
        val text = """
            /^ad.*\.com$/
            /^ad.*\.com$/${'$'}badfilter
            ||example.com^${'$'}denyallow=sub.example.com
            ||example.com^${'$'}denyallow=sub.example.com,badfilter
            ||example.com^${'$'}dnstype=AAAA
            ||example.com^${'$'}dnstype=AAAA,badfilter
        """.trimIndent()
        val cat = AdGuardRuleParser.parseCategorized(text)
        assertEquals(0, cat.blockRules.size)
        assertEquals(3, cat.badfilteredCount)
    }
}
