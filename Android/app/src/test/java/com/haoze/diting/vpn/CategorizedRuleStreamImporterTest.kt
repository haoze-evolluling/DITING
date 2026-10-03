package com.haoze.diting.vpn

import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.RewriteRuleEntity
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.BufferedReader
import java.io.StringReader
import java.lang.reflect.Proxy

class CategorizedRuleStreamImporterTest {

    private val insertedBlocks = mutableListOf<BlockRuleEntity>()
    private val insertedAllows = mutableListOf<AllowRuleEntity>()
    private val insertedRewrites = mutableListOf<RewriteRuleEntity>()

    private val blockDao = Proxy.newProxyInstance(
        BlockRuleDao::class.java.classLoader,
        arrayOf(BlockRuleDao::class.java)
    ) { _, method, args ->
        if (method.name == "insertAllForSource") {
            @Suppress("UNCHECKED_CAST")
            val list = args[0] as List<BlockRuleEntity>
            insertedBlocks.addAll(list)
            list.size
        } else {
            null
        }
    } as BlockRuleDao

    private val allowDao = Proxy.newProxyInstance(
        AllowRuleDao::class.java.classLoader,
        arrayOf(AllowRuleDao::class.java)
    ) { _, method, args ->
        if (method.name == "insertAllForSource") {
            @Suppress("UNCHECKED_CAST")
            val list = args[0] as List<AllowRuleEntity>
            insertedAllows.addAll(list)
            list.size
        } else {
            null
        }
    } as AllowRuleDao

    private val rewriteDao = Proxy.newProxyInstance(
        RewriteRuleDao::class.java.classLoader,
        arrayOf(RewriteRuleDao::class.java)
    ) { _, method, args ->
        if (method.name == "insertAllForSource") {
            @Suppress("UNCHECKED_CAST")
            val list = args[0] as List<RewriteRuleEntity>
            insertedRewrites.addAll(list)
            list.size
        } else {
            null
        }
    } as RewriteRuleDao

    private val blockManager = BlockListManager(blockDao, reloadCacheAfterChanges = false)
    private val allowManager = AllowListManager(allowDao, reloadCacheAfterChanges = false)
    private val rewriteManager = RewriteRuleManager(rewriteDao, reloadCacheAfterChanges = false)
    private val importer = CategorizedRuleStreamImporter(blockManager, allowManager, rewriteManager)

    @Test
    fun importWithBadfilterKeysDropsTargetRules() = runBlocking {
        insertedBlocks.clear()
        insertedAllows.clear()
        insertedRewrites.clear()

        val text = """
            ||good.com^
            ||bad.com^
            @@||allow.com^
            @@||bad-allow.com^
            ||rewrite.com^${'$'}dnsrewrite=1.2.3.4
            ||bad-rewrite.com^${'$'}dnsrewrite=1.2.3.4
        """.trimIndent()

        val badfilterKeys = setOf(
            "block:bad.com:false:null:false",
            "allow:bad-allow.com:false:null:false",
            "rewrite:bad-rewrite.com:IPv4:1.2.3.4"
        )

        val reader = BufferedReader(StringReader(text))
        val summary = importer.import(
            reader = reader,
            source = "test_sub",
            kind = "domain",
            enabled = true,
            badfilterKeys = badfilterKeys,
            onEmpty = { error("Unexpected empty") }
        )

        assertEquals(1, summary.blockCount)
        assertEquals(1, summary.allowCount)
        assertEquals(1, summary.rewriteCount)
        assertEquals(3, summary.badfilteredCount)

        assertEquals(listOf("good.com"), insertedBlocks.map { it.pattern })
        assertEquals(listOf("allow.com"), insertedAllows.map { it.pattern })
        assertEquals(listOf("rewrite.com"), insertedRewrites.map { it.pattern })
    }

    @Test
    fun importTwoPassReconcilesBadfilterAcrossEntireFile() = runBlocking {
        insertedBlocks.clear()
        insertedAllows.clear()
        insertedRewrites.clear()

        // badfilter lines can appear before or after the targeted rules
        val text = """
            ||bad-early.com^${'$'}badfilter
            ||good.com^
            ||bad-early.com^
            ||bad-late.com^
            ||bad-late.com^${'$'}badfilter
        """.trimIndent()

        val summary = importer.importTwoPass(
            openReader = { BufferedReader(StringReader(text)) },
            source = "test_sub",
            kind = "domain",
            enabled = true,
            onEmpty = { error("Unexpected empty") }
        )

        assertEquals(1, summary.blockCount)
        assertEquals(2, summary.badfilteredCount)
        assertEquals(listOf("good.com"), insertedBlocks.map { it.pattern })
    }

    @Test
    fun countRulesAccountsForBadfilterKeys() {
        val text = """
            ||good.com^
            ||bad.com^
            ||bad.com^${'$'}badfilter
        """.trimIndent()

        val rawCount = CategorizedRuleStreamImporter.countRules(BufferedReader(StringReader(text)))
        assertEquals(2, rawCount)

        val badfilterKeys = AdGuardRuleParser.extractBadfilterKeys(text)
        val filteredCount = CategorizedRuleStreamImporter.countRules(BufferedReader(StringReader(text)), badfilterKeys)
        assertEquals(1, filteredCount)
    }
}
