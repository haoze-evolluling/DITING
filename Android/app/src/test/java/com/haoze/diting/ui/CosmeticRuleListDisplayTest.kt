package com.haoze.diting.ui

import com.haoze.diting.data.RuleDataSources
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.MirrorTemplateDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleSourceEntity
import com.haoze.diting.ui.batch.BatchRecognitionMode
import com.haoze.diting.ui.batch.BatchRuleItem
import com.haoze.diting.ui.batch.BatchRuleTarget
import com.haoze.diting.ui.batch.BatchRuleValidator
import com.haoze.diting.vpn.AdGuardRuleParser
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Proxy

class CosmeticRuleListDisplayTest {

    private val targetHidingRules = listOf(
        "com.generalcomp.batian##.ad-container",
        "com.generalcomp.batian##.ad-banner",
        "com.generalcomp.batian##[class*=\"ad-\"]",
        "com.generalcomp.batian##[id*=\"ad-\"]"
    )

    private val targetAllowRule = "com.generalcomp.batian#@#.ad-container"

    private fun createMockDataSources(): RuleDataSources {
        val blockDao = Proxy.newProxyInstance(
            BlockRuleDao::class.java.classLoader,
            arrayOf(BlockRuleDao::class.java)
        ) { _, method, _ ->
            when (method.name) {
                "idByPattern" -> 0L
                else -> null
            }
        } as BlockRuleDao

        val allowDao = Proxy.newProxyInstance(
            AllowRuleDao::class.java.classLoader,
            arrayOf(AllowRuleDao::class.java)
        ) { _, method, _ ->
            when (method.name) {
                "idByPattern" -> 0L
                else -> null
            }
        } as AllowRuleDao

        val rewriteDao = Proxy.newProxyInstance(
            RewriteRuleDao::class.java.classLoader,
            arrayOf(RewriteRuleDao::class.java)
        ) { _, _, _ -> null } as RewriteRuleDao

        val goUrlDao = Proxy.newProxyInstance(
            GoUrlRuleDao::class.java.classLoader,
            arrayOf(GoUrlRuleDao::class.java)
        ) { _, method, _ ->
            when (method.name) {
                "idByPattern" -> 0L
                else -> null
            }
        } as GoUrlRuleDao

        val cosmeticDao = Proxy.newProxyInstance(
            CosmeticRuleDao::class.java.classLoader,
            arrayOf(CosmeticRuleDao::class.java)
        ) { _, method, _ ->
            when (method.name) {
                "idByDomainAndSelector" -> 0L
                else -> null
            }
        } as CosmeticRuleDao

        return object : RuleDataSources {
            override fun blockRuleDao(): BlockRuleDao = blockDao
            override fun allowRuleDao(): AllowRuleDao = allowDao
            override fun rewriteRuleDao(): RewriteRuleDao = rewriteDao
            override fun goUrlRuleDao(): GoUrlRuleDao = goUrlDao
            override fun cosmeticRuleDao(): CosmeticRuleDao = cosmeticDao
            override fun subscriptionDao(): SubscriptionDao = throw UnsupportedOperationException()
            override fun subscriptionGroupDao(): SubscriptionGroupDao = throw UnsupportedOperationException()
            override fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao = throw UnsupportedOperationException()
            override fun mirrorTemplateDao(): MirrorTemplateDao = throw UnsupportedOperationException()
        }
    }

    @Test
    fun testParseCosmeticRulesDirectly() {
        // 1. Verify parser classifies element hiding rules as cosmetic block
        targetHidingRules.forEach { line ->
            val parsed = AdGuardRuleParser.parseCategorized(line)
            assertEquals("Rule: $line should produce 1 cosmetic rule", 1, parsed.cosmeticRules.size)
            val rule = parsed.cosmeticRules.first()
            assertEquals("com.generalcomp.batian", rule.domain)
            assertFalse("Element hiding rule must not be an exception", rule.isException)
            assertEquals(line, rule.rawLine)
        }

        // 2. Verify parser classifies element exception rule as cosmetic allow
        val parsedAllow = AdGuardRuleParser.parseCategorized(targetAllowRule)
        assertEquals(1, parsedAllow.cosmeticRules.size)
        val allowRule = parsedAllow.cosmeticRules.first()
        assertEquals("com.generalcomp.batian", allowRule.domain)
        assertEquals(".ad-container", allowRule.selector)
        assertTrue("Element exception rule must be an exception", allowRule.isException)
        assertEquals(targetAllowRule, allowRule.rawLine)
    }

    @Test
    fun testBatchValidatorDistinguishesHidingAndAllowRules() = runBlocking {
        val mockSources = createMockDataSources()
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL, BatchRuleTarget.BLACKLIST)

        val input = (targetHidingRules + targetAllowRule).joinToString("\n")
        val summary = validator.validate(input, BatchRecognitionMode.AUTO)

        // Hiding rules are classified as BLOCK, exception rule as ALLOW
        assertEquals(5, summary.validCount)
        assertEquals(4, summary.blockCount)
        assertEquals(1, summary.allowCount)
        assertEquals(0, summary.invalidCount)
        assertEquals(0, summary.duplicateCount)

        val cosmeticItems = summary.validItems.filterIsInstance<BatchRuleItem.ValidCosmetic>()
        assertEquals(5, cosmeticItems.size)

        val blockCosmetics = cosmeticItems.filter { !it.isException }
        val allowCosmetics = cosmeticItems.filter { it.isException }
        assertEquals(4, blockCosmetics.size)
        assertEquals(1, allowCosmetics.size)
    }

    @Test
    fun testCosmeticRuleEntityMappingToBlacklistItem() {
        val entity = CosmeticRuleEntity(
            id = 42L,
            domain = "com.generalcomp.batian",
            selector = ".ad-container",
            rawLine = "com.generalcomp.batian##.ad-container",
            addedAt = 1000L,
            enabled = true
        )

        // Use toItem logic as mapped in BlacklistViewModel
        val item = BlacklistItem(
            id = entity.id,
            pattern = entity.rawLine.ifBlank { if (entity.domain.isNotEmpty()) "${entity.domain}##${entity.selector}" else "##${entity.selector}" },
            rawLine = entity.rawLine,
            type = BlacklistType.COSMETIC,
            groupName = null,
            appScope = entity.domain.takeIf { it.isNotBlank() },
            appInverted = false,
            isWildcard = false,
            important = false,
            enabled = entity.enabled,
            masterEnabled = true,
            effectiveEnabled = true,
            addedAt = entity.addedAt,
            isUserRule = true,
            isSubscription = false,
            subscriptionName = null
        )

        assertEquals(42L, item.id)
        assertEquals("com.generalcomp.batian##.ad-container", item.pattern)
        assertEquals(BlacklistType.COSMETIC, item.type)
        assertEquals("com.generalcomp.batian", item.appScope)
        assertTrue(item.isUserRule)
        assertTrue(item.effectiveEnabled)
    }

    @Test
    fun testCosmeticRuleEntityMappingToWhitelistItem() {
        val entity = CosmeticRuleEntity(
            id = 99L,
            domain = "com.generalcomp.batian",
            selector = ".ad-container",
            rawLine = "com.generalcomp.batian#@#.ad-container",
            addedAt = 2000L,
            enabled = true
        )

        val item = entity.toItem(
            isUserRule = true,
            isSubscription = false,
            subscriptionName = null,
            masterEnabled = true
        )

        assertEquals(99L, item.id)
        assertEquals("com.generalcomp.batian#@#.ad-container", item.pattern)
        assertEquals(WhitelistType.COSMETIC, item.type)
        assertEquals("com.generalcomp.batian", item.appScope)
        assertTrue(item.isUserRule)
        assertTrue(item.effectiveEnabled)
    }

    @Test
    fun testCosmeticFilterExclusionInDnsMode() {
        // Ensure that BlacklistFilter.COSMETIC and WhitelistFilter.COSMETIC are filtered out in DNS mode
        val blacklistFilters = BlacklistFilter.entries.filterNot {
            RuleDataset.DNS_MODE != RuleDataset.NORMAL && (it == BlacklistFilter.URL || it == BlacklistFilter.COSMETIC)
        }
        assertFalse(blacklistFilters.contains(BlacklistFilter.COSMETIC))
        assertFalse(blacklistFilters.contains(BlacklistFilter.URL))
        assertTrue(blacklistFilters.contains(BlacklistFilter.DOMAIN))

        val whitelistFilters = WhitelistFilter.entries.filterNot {
            it == WhitelistFilter.URL || it == WhitelistFilter.PRESET || it == WhitelistFilter.COSMETIC
        }
        assertFalse(whitelistFilters.contains(WhitelistFilter.COSMETIC))
        assertFalse(whitelistFilters.contains(WhitelistFilter.URL))
        assertTrue(whitelistFilters.contains(WhitelistFilter.DOMAIN))
    }

    @Test
    fun testSearchFilteringForCosmeticRules() {
        val items = targetHidingRules.mapIndexed { idx, rule ->
            val parts = rule.split("##")
            val domain = parts[0]
            val selector = parts[1]
            BlacklistItem(
                id = idx.toLong() + 1,
                pattern = rule,
                rawLine = rule,
                type = BlacklistType.COSMETIC,
                groupName = null,
                appScope = domain,
                appInverted = false,
                isWildcard = false,
                important = false,
                enabled = true,
                masterEnabled = true,
                effectiveEnabled = true,
                addedAt = 1000L,
                isUserRule = true,
                isSubscription = false,
                subscriptionName = null
            )
        }

        // Search by domain "batian" -> all 4 match
        val queryDomain = "batian"
        val domainMatches = items.filter { item ->
            item.pattern.lowercase().contains(queryDomain) ||
                    (item.appScope?.lowercase()?.contains(queryDomain) == true)
        }
        assertEquals(4, domainMatches.size)

        // Search by selector "ad-banner" -> only 1 matches
        val querySelector = "ad-banner"
        val bannerMatches = items.filter { item ->
            item.pattern.lowercase().contains(querySelector)
        }
        assertEquals(1, bannerMatches.size)
        assertEquals("com.generalcomp.batian##.ad-banner", bannerMatches.first().pattern)

        // Search by selector class wildcard "[class*="
        val queryClass = "class*="
        val classMatches = items.filter { item ->
            item.pattern.lowercase().contains(queryClass)
        }
        assertEquals(1, classMatches.size)
        assertEquals("com.generalcomp.batian##[class*=\"ad-\"]", classMatches.first().pattern)
    }
}
