package com.haoze.diting.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class SpecialRuleMatcherTest {

    @Test
    fun testDenyallowMatching() {
        val rule = ExportedSpecialBlockRule(
            pattern = "example.com",
            source = "rule_denyallow",
            important = false,
            appScope = null,
            appInverted = false,
            isWildcard = false,
            denyallow = "good.example.com|safe.example.com",
            isRegex = false,
            dnsType = null
        )

        val state = BlockRuleCacheState(
            specialRules = listOf(rule)
        )

        // Matches base and other subdomains
        assertNotNull(BlockRuleMatcher.findGlobalMatch(state, "example.com"))
        assertNotNull(BlockRuleMatcher.findGlobalMatch(state, "bad.example.com"))

        // Exempts denyallow domain and its subdomains
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "good.example.com"))
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "sub.good.example.com"))
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "safe.example.com"))
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "sub.safe.example.com"))
    }

    @Test
    fun testRegexMatching() {
        val rule = ExportedSpecialBlockRule(
            pattern = "^ad\\d+\\.example\\.com$",
            source = "regex_rule",
            important = false,
            appScope = null,
            appInverted = false,
            isWildcard = false,
            denyallow = null,
            isRegex = true,
            dnsType = null
        )

        val state = BlockRuleCacheState(
            specialRules = listOf(rule)
        )

        assertNotNull(BlockRuleMatcher.findGlobalMatch(state, "ad123.example.com"))
        assertNotNull(BlockRuleMatcher.findGlobalMatch(state, "AD456.EXAMPLE.COM"))
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "ad.example.com"))
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "other.example.com"))
    }

    @Test
    fun testAppScopedSpecialRuleMatching() {
        val appRule = ExportedSpecialBlockRule(
            pattern = "^ad\\d+\\.app\\.com$",
            source = "app_regex_rule",
            important = false,
            appScope = "com.test.app",
            appInverted = false,
            isWildcard = false,
            denyallow = null,
            isRegex = true,
            dnsType = null
        )

        val state = BlockRuleCacheState(
            specialRules = listOf(appRule)
        )

        // App-specific match
        val match = BlockRuleMatcher.findAppMatch(state, "ad1.app.com", "com.test.app")
        assertNotNull(match)
        assertEquals("app_regex_rule", match?.source)

        // Global match does not match app-specific rules
        assertNull(BlockRuleMatcher.findGlobalMatch(state, "ad1.app.com", "com.test.app"))

        // Other apps do not match
        assertNull(BlockRuleMatcher.findAppMatch(state, "ad1.app.com", "com.other.app"))
    }
}
