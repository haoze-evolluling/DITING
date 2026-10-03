package com.haoze.diting.ui

import com.haoze.diting.data.RuleDataSources
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.MirrorTemplateDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.ui.batch.BatchRuleItem
import com.haoze.diting.ui.batch.BatchRuleTarget
import com.haoze.diting.ui.batch.BatchRuleValidator
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Proxy

class BatchRuleValidatorTest {

    private fun createMockDataSources(
        existingBlockPatterns: Set<String> = emptySet(),
        existingAllowPatterns: Set<String> = emptySet(),
        existingRewriteKeys: Set<String> = emptySet(),
        existingRewriteTypes: Map<String, Set<String>> = emptyMap()
    ): RuleDataSources {
        val blockDao = Proxy.newProxyInstance(
            BlockRuleDao::class.java.classLoader,
            arrayOf(BlockRuleDao::class.java)
        ) { _, method, args ->
            when (method.name) {
                "idByPattern" -> {
                    val pattern = args[0] as String
                    if (pattern in existingBlockPatterns) 100L else 0L
                }
                else -> null
            }
        } as BlockRuleDao

        val allowDao = Proxy.newProxyInstance(
            AllowRuleDao::class.java.classLoader,
            arrayOf(AllowRuleDao::class.java)
        ) { _, method, args ->
            when (method.name) {
                "idByPattern" -> {
                    val pattern = args[0] as String
                    if (pattern in existingAllowPatterns) 200L else 0L
                }
                else -> null
            }
        } as AllowRuleDao

        val rewriteDao = Proxy.newProxyInstance(
            RewriteRuleDao::class.java.classLoader,
            arrayOf(RewriteRuleDao::class.java)
        ) { _, method, args ->
            when (method.name) {
                "idByKey" -> {
                    val domain = args[0] as String
                    val type = args[1] as String
                    val value = args[2] as String
                    val key = "$domain:$type:$value"
                    if (key in existingRewriteKeys) 300L else 0L
                }
                "countType" -> {
                    val domain = args[0] as String
                    val type = args[1] as String
                    val types = existingRewriteTypes[domain] ?: emptySet()
                    if (type in types) 1 else 0
                }
                "countOtherTypes" -> {
                    val domain = args[0] as String
                    val type = args[1] as String
                    val types = existingRewriteTypes[domain] ?: emptySet()
                    if (types.any { it != type }) 1 else 0
                }
                else -> null
            }
        } as RewriteRuleDao

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
            com.haoze.diting.data.dao.CosmeticRuleDao::class.java.classLoader,
            arrayOf(com.haoze.diting.data.dao.CosmeticRuleDao::class.java)
        ) { _, method, _ ->
            when (method.name) {
                "idByDomainAndSelector" -> 0L
                else -> null
            }
        } as com.haoze.diting.data.dao.CosmeticRuleDao

        return object : RuleDataSources {
            override fun blockRuleDao() = blockDao
            override fun allowRuleDao() = allowDao
            override fun rewriteRuleDao() = rewriteDao
            override fun goUrlRuleDao() = goUrlDao
            override fun cosmeticRuleDao() = cosmeticDao
            override fun subscriptionDao(): SubscriptionDao = throw UnsupportedOperationException()
            override fun subscriptionGroupDao(): SubscriptionGroupDao = throw UnsupportedOperationException()
            override fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao = throw UnsupportedOperationException()
            override fun mirrorTemplateDao(): MirrorTemplateDao = throw UnsupportedOperationException()
        }
    }

    @Test
    fun testBlacklistValidationNormalMode() = runBlocking {
        val mockSources = createMockDataSources(existingBlockPatterns = setOf("already-blocked.com"))
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL, BatchRuleTarget.BLACKLIST)

        val input = """
            # This is a comment
            example.com
            *.ads.net
            ||tracker.com^
            0.0.0.0 badhost.com
            https://example.com/ad-path
            already-blocked.com
            example.com
            
            ! Another comment
            invalid..domain%%
        """.trimIndent()

        val summary = validator.validate(input)

        assertEquals(11, summary.totalLines)
        assertEquals(3, summary.ignoredCount) // 2 comments + 1 empty line
        assertEquals(5, summary.validCount) // example.com, *.ads.net, tracker.com, badhost.com, https://example.com/ad-path
        assertEquals(2, summary.duplicateCount) // already-blocked.com (db), example.com (in-batch)
        assertEquals(1, summary.invalidCount) // invalid..domain%%
    }

    @Test
    fun testBlacklistDnsModeRejectsUrl() = runBlocking {
        val mockSources = createMockDataSources()
        val validator = BatchRuleValidator(mockSources, RuleDataset.DNS_MODE, BatchRuleTarget.BLACKLIST)

        val input = """
            example.com
            https://example.com/ad-path
        """.trimIndent()

        val summary = validator.validate(input)

        assertEquals(1, summary.validCount)
        assertEquals(1, summary.invalidCount)
        assertTrue(summary.invalidItems[0].reason.contains("仅普通模式支持"))
    }

    @Test
    fun testWhitelistValidation() = runBlocking {
        val mockSources = createMockDataSources(existingAllowPatterns = setOf("whitelisted.org"))
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL, BatchRuleTarget.WHITELIST)

        val input = """
            # Whitelist test
            safe.org
            @@||trusted.com^
            https://example.com/api
            whitelisted.org
            safe.org
        """.trimIndent()

        val summary = validator.validate(input)

        assertEquals(1, summary.ignoredCount)
        assertEquals(3, summary.validCount) // safe.org, trusted.com, https://example.com/api
        assertEquals(2, summary.duplicateCount) // whitelisted.org, duplicate safe.org
        assertEquals(0, summary.invalidCount)
    }

    @Test
    fun testRewriteValidation() = runBlocking {
        val mockSources = createMockDataSources(
            existingRewriteKeys = setOf("existing.com:${RewriteTargetType.IPV4}:1.2.3.4"),
            existingRewriteTypes = mapOf("cname-only.com" to setOf(RewriteTargetType.CNAME))
        )
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL, BatchRuleTarget.REWRITE)

        val input = """
            # Hosts style
            1.2.3.4 example.com
            # Arrow style
            api.server.com -> 10.0.0.1
            # CNAME
            alias.org -> target.com
            # AdGuard style
            ||adg.com^${'$'}dnsrewrite=8.8.8.8
            # Duplicate in DB
            existing.com -> 1.2.3.4
            # Duplicate in batch
            example.com 1.2.3.4
            # Conflict with CNAME
            cname-only.com -> 1.1.1.1
            # Invalid target
            foo.com -> not-an-ip-or-domain!
        """.trimIndent()

        val summary = validator.validate(input)
        assertEquals(4, summary.validCount) // example.com, api.server.com, alias.org, adg.com
        assertEquals(2, summary.duplicateCount) // existing.com, repeated example.com
        assertEquals(2, summary.invalidCount) // conflict with cname, invalid target
    }

    @Test
    fun testUnifiedMixedRulesValidation() = runBlocking {
        val mockSources = createMockDataSources(existingBlockPatterns = setOf("already-blocked.com"))
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL, BatchRuleTarget.BLACKLIST)

        val input = """
            # Comments
            ||block-domain.com^
            0.0.0.0 sinkhole.org
            @@||allow-domain.com^
            @@whitelisted.io
            192.168.1.1 router.local
            api.internal -> 10.0.0.1
            alias.net -> cname.target.com
            ||cdn.net^${'$'}dnsrewrite=1.1.1.1
            https://tracker.com/pixel.gif
            @@https://auth.com/login
            forum.com##.ads-banner
            forum.com#@#.vip-badge
            # In-batch duplicate
            ||block-domain.com^
            # DB duplicate
            already-blocked.com
            # Invalid
            invalid..domain%%%
        """.trimIndent()

        val summary = validator.validate(input, com.haoze.diting.ui.batch.BatchRecognitionMode.AUTO)

        // Valid items:
        // Blocks: block-domain.com, sinkhole.org, tracker.com URL, forum.com##.ads-banner -> 4
        // Allows: allow-domain.com, whitelisted.io, auth.com URL, forum.com#@#.vip-badge -> 4
        // Rewrites: router.local, api.internal, alias.net, cdn.net -> 4
        assertEquals(4, summary.blockCount)
        assertEquals(4, summary.allowCount)
        assertEquals(4, summary.rewriteCount)
        assertEquals(12, summary.validCount)
        assertEquals(2, summary.duplicateCount) // duplicate block-domain.com, already-blocked.com
        assertEquals(1, summary.invalidCount) // invalid..domain%%%
    }

    @Test
    fun testModeDisambiguation() = runBlocking {
        val mockSources = createMockDataSources()
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL)

        val input = """
            pure-domain.com
            ||explicit-block.com^
            @@||explicit-allow.com^
        """.trimIndent()

        // 1. AUTO mode: pure-domain.com is Blacklist
        val summaryAuto = validator.validate(input, com.haoze.diting.ui.batch.BatchRecognitionMode.AUTO)
        assertEquals(2, summaryAuto.blockCount) // pure-domain.com, explicit-block.com
        assertEquals(1, summaryAuto.allowCount) // explicit-allow.com

        // 2. WHITELIST_FIRST mode: pure-domain.com is Whitelist
        val summaryWhite = validator.validate(input, com.haoze.diting.ui.batch.BatchRecognitionMode.WHITELIST_FIRST)
        assertEquals(1, summaryWhite.blockCount) // explicit-block.com
        assertEquals(2, summaryWhite.allowCount) // pure-domain.com, explicit-allow.com

        // 3. BLACKLIST_FIRST mode: pure-domain.com is Blacklist
        val summaryBlack = validator.validate(input, com.haoze.diting.ui.batch.BatchRecognitionMode.BLACKLIST_FIRST)
        assertEquals(2, summaryBlack.blockCount) // pure-domain.com, explicit-block.com
        assertEquals(1, summaryBlack.allowCount) // explicit-allow.com
    }

    @Test
    fun testMultiDomainHostsLines() = runBlocking {
        val mockSources = createMockDataSources()
        val validator = BatchRuleValidator(mockSources, RuleDataset.NORMAL)

        val input = """
            10.0.0.1 host1.local host2.local
            0.0.0.0 sink1.ads sink2.ads
        """.trimIndent()

        val summary = validator.validate(input)
        assertEquals(2, summary.rewriteCount) // host1.local, host2.local
        assertEquals(2, summary.blockCount) // sink1.ads, sink2.ads
        assertEquals(4, summary.validCount)
    }
}

