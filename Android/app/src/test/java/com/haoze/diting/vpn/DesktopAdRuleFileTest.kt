package com.haoze.diting.vpn

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
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleSourceEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleSourceEntity
import com.haoze.diting.data.entity.RewriteRuleEntity
import com.haoze.diting.ui.batch.BatchRuleItem
import com.haoze.diting.ui.batch.BatchRuleTarget
import com.haoze.diting.ui.batch.BatchRuleValidator
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.File
import java.io.StringReader
import java.lang.reflect.Proxy

/**
 * Tests parsing and importing for the user's "广告过滤规则.txt" file.
 * Confirms that all 74 valid rules (41 domain block, 13 URL interception, 20 cosmetic)
 * and 37 comments/blank lines are accurately recognized with 0 dropped and 0 invalid.
 */
class DesktopAdRuleFileTest {

    private val desktopFilePath = "C:\\Users\\leehaoze\\Desktop\\广告过滤规则.txt"

    private fun loadRuleFileContent(): String {
        val file = File(desktopFilePath)
        return if (file.exists()) {
            file.readText()
        } else {
            """
                ! Title: 霸天安监控 + 红果短剧 广告过滤规则
                ! Description: 针对霸天安监控 (com.generalcomp.batian) 和红果短剧 (com.phoenix.read) 的广告过滤
                ! 更新时间: 2026-10-01

                ! ============================================================
                ! 第一部分：通用广告联盟域名（覆盖两个App的主要广告源）
                ! ============================================================

                ! ==== 穿山甲广告 SDK（字节系）====
                ||pangle-ads.com^
                ||pangle.io^
                ||*.pangle.io^
                ||pangleglobal.com^
                ||*.pangleglobal.com^
                ||ads.pangle.cn^
                ||*.pangle.cn^
                ||csjplatform.com^
                ||*.csjplatform.com^

                ! ==== 字节跳动广告域名 ====
                ||ads.bytedance.com^
                ||*.ads.bytedance.com^
                ||ad.bytedance.com^
                ||adservice.bytedance.com^
                ||adlog.bytedance.com^
                ||adx.bytedance.com^
                ||ads-api.bytedance.com^
                ||ad.oceanengine.com^
                ||ads.oceanengine.com^

                ! ==== 优量汇广告 SDK（腾讯系）====
                ||gdt.qq.com^
                ||*.gdt.qq.com^
                ||v2.gdt.qq.com^
                ||sc.gdt.qq.com^
                ||adnet.qq.com^
                ||*.adnet.qq.com^
                ||e.qq.com^
                ||*.e.qq.com^
                ||pgdt.gtimg.cn^
                ||adsmind.tc.qq.com^

                ! ==== 其他常见广告联盟 ====
                ||kwaiad.cn^
                ||*.kwaiad.cn^
                ||kwaibusiness.cn^
                ||*.kwaibusiness.cn^
                ||ad.kuaishou.com^
                ||pos.baidu.com^
                ||cpro.baidu.com^

                ! ==== 广告追踪与统计 ====
                ||admaster.com.cn^
                ||*.admaster.com.cn^
                ||miaozhen.com^
                ||*.miaozhen.com^
                ||doubleclick.net^
                ||*.doubleclick.net^

                ! ============================================================
                ! 第二部分：霸天安监控专属规则 (com.generalcomp.batian)
                ! ============================================================

                ! ==== 广告接口路径拦截 ====
                ||*.generalcomp.batian/ad^
                ||*.generalcomp.batian/ads^
                ||*.generalcomp.batian/advert^

                ! ==== App内广告元素隐藏 ====
                com.generalcomp.batian##.ad-container
                com.generalcomp.batian##.ad-banner
                com.generalcomp.batian##.ad-splash
                com.generalcomp.batian##.splash-ad
                com.generalcomp.batian##[class*="ad-"]
                com.generalcomp.batian##[id*="ad-"]
                com.generalcomp.batian##[class*="advert"]
                com.generalcomp.batian##[id*="advert"]
                com.generalcomp.batian##[class*="splash"]
                com.generalcomp.batian##[id*="splash"]
                com.generalcomp.batian##[class*="popup"]
                com.generalcomp.batian##[id*="popup"]

                ! ============================================================
                ! 第三部分：红果短剧专属规则 (com.phoenix.read)
                ! ============================================================

                ! ==== 广告接口路径拦截 ====
                ||*.phoenix.read/ad^
                ||*.phoenix.read/ads^
                ||*.phoenix.read/advert^

                ! ==== App内广告元素隐藏 ====
                com.phoenix.read##.ad-container
                com.phoenix.read##.ad-banner
                com.phoenix.read##.ad-splash
                com.phoenix.read##.splash-ad
                com.phoenix.read##[class*="ad-"]
                com.phoenix.read##[id*="ad-"]
                com.phoenix.read##[class*="advert"]
                com.phoenix.read##[id*="advert"]

                ! ============================================================
                ! 第四部分：通用开屏/插屏广告拦截
                ! ============================================================
                ||*/api/ad/splash^
                ||*/api/ad/launch^
                ||*/api/splash/ad^
                ||*/ad/splash^
                ||*/ad/launch^
                ||*/api/ad/interstitial^
                ||*/ad/interstitial^
            """.trimIndent()
        }
    }

    @Test
    fun parseAdRuleFileCompletely() {
        val content = loadRuleFileContent()
        val categorized = AdGuardRuleParser.parseCategorized(content)

        assertEquals("Total lines in file", 111, categorized.totalLines)
        assertEquals("Ignored comments and headers", 37, categorized.ignoredCount)
        assertEquals("Invalid rule lines", 0, categorized.invalidCount)
        assertEquals("Unsupported rule lines", 0, categorized.unsupportedCount)
        assertEquals("Duplicate rules", 0, categorized.duplicateCount)

        assertEquals("Domain block rules count", 41, categorized.blockRules.size)
        assertEquals("URL interception rules count", 13, categorized.urlBlockRules.size)
        assertEquals("Cosmetic element-hiding rules count", 20, categorized.cosmeticRules.size)
        assertEquals("Allow rules count", 0, categorized.allowRules.size)
        assertEquals("Rewrite rules count", 0, categorized.rewriteRules.size)

        assertEquals("Total valid rules", 74, categorized.size)
    }

    @Test
    fun batchValidateDesktopAdRuleFile() = runBlocking {
        val content = loadRuleFileContent()

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
        ) { _, method, _ ->
            when (method.name) {
                "idByKey" -> 0L
                "countType" -> 0
                "countOtherTypes" -> 0
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
            CosmeticRuleDao::class.java.classLoader,
            arrayOf(CosmeticRuleDao::class.java)
        ) { _, method, _ ->
            when (method.name) {
                "idByDomainAndSelector" -> 0L
                else -> null
            }
        } as CosmeticRuleDao

        val mockDataSources = object : RuleDataSources {
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

        val validator = BatchRuleValidator(mockDataSources, RuleDataset.NORMAL, BatchRuleTarget.BLACKLIST)
        val summary = validator.validate(content)

        assertEquals("Total lines", 111, summary.totalLines)
        assertEquals("Ignored comment lines", 37, summary.ignoredCount)
        assertEquals("Invalid lines", 0, summary.invalidCount)
        assertEquals("Duplicate lines", 0, summary.duplicateCount)
        assertEquals("Total valid items", 74, summary.validCount)

        val domainCount = summary.validItems.count { it is BatchRuleItem.ValidDomain }
        val urlCount = summary.validItems.count { it is BatchRuleItem.ValidUrl }
        val cosmeticCount = summary.validItems.count { it is BatchRuleItem.ValidCosmetic }

        assertEquals("Domain rules in batch", 41, domainCount)
        assertEquals("URL rules in batch", 13, urlCount)
        assertEquals("Cosmetic rules in batch", 20, cosmeticCount)
    }

    @Test
    fun streamImportDesktopAdRuleFile() = runBlocking {
        val content = loadRuleFileContent()

        val insertedBlocks = mutableListOf<BlockRuleEntity>()
        val insertedUrlRules = mutableListOf<GoUrlRuleEntity>()
        val insertedCosmeticRules = mutableListOf<CosmeticRuleEntity>()

        val blockDao = Proxy.newProxyInstance(
            BlockRuleDao::class.java.classLoader,
            arrayOf(BlockRuleDao::class.java)
        ) { _, method, args ->
            when (method.name) {
                "insertAllForSource" -> {
                    @Suppress("UNCHECKED_CAST")
                    val list = args[0] as List<BlockRuleEntity>
                    insertedBlocks.addAll(list)
                    list.size
                }
                else -> null
            }
        } as BlockRuleDao

        val allowDao = Proxy.newProxyInstance(
            AllowRuleDao::class.java.classLoader,
            arrayOf(AllowRuleDao::class.java)
        ) { _, _, _ -> null } as AllowRuleDao

        val rewriteDao = Proxy.newProxyInstance(
            RewriteRuleDao::class.java.classLoader,
            arrayOf(RewriteRuleDao::class.java)
        ) { _, _, _ -> null } as RewriteRuleDao

        val fakeGoUrlDao = object : GoUrlRuleDao {
            override suspend fun insertRule(rule: GoUrlRuleEntity): Long = 1L
            override suspend fun insertSource(source: GoUrlRuleSourceEntity): Long = 1L
            override suspend fun idByPattern(pattern: String, kind: String): Long = 0L
            override suspend fun insertForSource(rule: GoUrlRuleEntity, source: String, sourceEnabled: Boolean): Boolean {
                insertedUrlRules.add(rule)
                return true
            }
            override suspend fun enabledRules(): List<GoUrlRuleEntity> = insertedUrlRules
            override suspend fun enabledRulesBySource(source: String): List<GoUrlRuleEntity> = insertedUrlRules
            override suspend fun rulesBySource(source: String): List<GoUrlRuleEntity> = insertedUrlRules
            override suspend fun byKind(kind: String): List<GoUrlRuleEntity> = insertedUrlRules.filter { it.kind == kind }
            override suspend fun count(kind: String): Int = insertedUrlRules.count { it.kind == kind }
            override suspend fun enabledCount(kind: String): Int = insertedUrlRules.count { it.kind == kind && it.enabled }
            override suspend fun sourcesForRuleIds(ruleIds: List<Long>): List<GoUrlRuleSourceEntity> = emptyList()
            override suspend fun setEnabled(id: Long, enabled: Boolean) {}
            override suspend fun setSourceEnabledByRuleId(ruleId: Long, enabled: Boolean) {}
            override suspend fun deleteById(id: Long) {}
            override suspend fun deleteSourceOnly(source: String) {}
            override suspend fun deleteOrphans() {}
            override suspend fun deleteSourcesByKindAndSource(kind: String, source: String) {}
            override suspend fun promoteSource(oldSource: String, newSource: String) {}
            override suspend fun setSourceEnabledBySource(source: String, enabled: Boolean) {}
            override suspend fun clearAll() {}
        }

        val fakeCosmeticDao = object : CosmeticRuleDao {
            override suspend fun insertRule(rule: CosmeticRuleEntity): Long = 1L
            override suspend fun insertSource(source: CosmeticRuleSourceEntity): Long = 1L
            override suspend fun idByDomainAndSelector(domain: String, selector: String): Long = 0L
            override suspend fun insertForSource(rule: CosmeticRuleEntity, source: String, sourceEnabled: Boolean): Boolean {
                insertedCosmeticRules.add(rule)
                return true
            }
            override suspend fun enabledRules(): List<CosmeticRuleEntity> = insertedCosmeticRules
            override suspend fun enabledRulesBySource(source: String): List<CosmeticRuleEntity> = insertedCosmeticRules
            override suspend fun rulesBySource(source: String): List<CosmeticRuleEntity> = insertedCosmeticRules
            override suspend fun allRules(): List<CosmeticRuleEntity> = insertedCosmeticRules
            override suspend fun count(): Int = insertedCosmeticRules.size
            override suspend fun enabledCount(): Int = insertedCosmeticRules.count { it.enabled }
            override suspend fun setEnabled(id: Long, enabled: Boolean) {}
            override suspend fun setSourceEnabledByRuleId(ruleId: Long, enabled: Boolean) {}
            override suspend fun deleteById(id: Long) {}
            override suspend fun deleteSourceOnly(source: String) {}
            override suspend fun deleteOrphans() {}
            override suspend fun promoteSource(oldSource: String, newSource: String) {}
            override suspend fun setSourceEnabledBySource(source: String, enabled: Boolean) {}
            override suspend fun clearAll() {}
            override suspend fun deleteSourcesByRuleId(ruleId: Long) {}
            override suspend fun sourcesForRuleIds(ruleIds: List<Long>): List<CosmeticRuleSourceEntity> = emptyList()
            override suspend fun blockRules(): List<CosmeticRuleEntity> = insertedCosmeticRules.filter { !it.rawLine.contains("#@#") }
            override suspend fun allowRules(): List<CosmeticRuleEntity> = insertedCosmeticRules.filter { it.rawLine.contains("#@#") }
            override suspend fun blockRulesCount(): Int = insertedCosmeticRules.count { !it.rawLine.contains("#@#") }
            override suspend fun allowRulesCount(): Int = insertedCosmeticRules.count { it.rawLine.contains("#@#") }
            override suspend fun enabledBlockCount(): Int = insertedCosmeticRules.count { it.enabled && !it.rawLine.contains("#@#") }
            override suspend fun enabledAllowCount(): Int = insertedCosmeticRules.count { it.enabled && it.rawLine.contains("#@#") }
            override suspend fun deleteUserBlockSources() {}
            override suspend fun deleteUserAllowSources() {}
        }

        val blockManager = BlockListManager(blockDao, reloadCacheAfterChanges = false)
        val allowManager = AllowListManager(allowDao, reloadCacheAfterChanges = false)
        val rewriteManager = RewriteRuleManager(rewriteDao, reloadCacheAfterChanges = false)

        val counted = CategorizedRuleStreamImporter.countRules(BufferedReader(StringReader(content)))
        assertEquals("Stream counted rules", 74, counted)

        val importer = CategorizedRuleStreamImporter(
            blockListManager = blockManager,
            allowListManager = allowManager,
            rewriteRuleManager = rewriteManager,
            goUrlRuleDao = fakeGoUrlDao,
            cosmeticRuleDao = fakeCosmeticDao,
            chunkSize = 500
        )

        val summary = importer.import(
            reader = BufferedReader(StringReader(content)),
            source = "test_desktop",
            kind = "all",
            enabled = true,
            onEmpty = { throw IllegalStateException("Should not be empty") }
        )

        assertEquals("Imported total count", 74, summary.importedCount)
        assertEquals("Block domain count", 41, summary.blockCount)
        assertEquals("URL block count", 13, summary.urlBlockCount)
        assertEquals("Cosmetic rule count", 20, summary.cosmeticCount)
        assertEquals("Duplicate count", 0, summary.duplicateCount)
        assertEquals("Invalid count", 0, summary.invalidCount)
        assertEquals("Unsupported count", 0, summary.unsupportedCount)

        assertEquals("Inserted block entities", 41, insertedBlocks.size)
        assertEquals("Inserted URL entities", 13, insertedUrlRules.size)
        assertEquals("Inserted cosmetic entities", 20, insertedCosmeticRules.size)

        // Verify CosmeticRuleManager CSS compilation
        val cosmeticManager = CosmeticRuleManager(fakeCosmeticDao)
        val compiledCss = cosmeticManager.compileAllToCss()
        assertTrue("CSS contains ad-container", compiledCss.contains(".ad-container { display: none !important; }"))
        assertTrue("CSS contains ad-banner", compiledCss.contains(".ad-banner { display: none !important; }"))
        assertTrue("CSS contains class*=ad-", compiledCss.contains("[class*=\"ad-\"] { display: none !important; }"))
        assertTrue("CSS contains id*=splash", compiledCss.contains("[id*=\"splash\"] { display: none !important; }"))
    }
}
