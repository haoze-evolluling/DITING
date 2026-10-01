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

        return object : RuleDataSources {
            override fun blockRuleDao() = blockDao
            override fun allowRuleDao() = allowDao
            override fun rewriteRuleDao() = rewriteDao
            override fun goUrlRuleDao() = goUrlDao
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
}
