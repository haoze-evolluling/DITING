package com.haoze.diting.data.cleanup

import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.data.entity.SubscriptionKind
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.lang.reflect.Proxy
import java.nio.file.Files

class DataCleanupManagerTest {

    @Suppress("UNCHECKED_CAST")
    private fun <T> createProxy(clazz: Class<T>, invocations: MutableList<String>): T {
        return Proxy.newProxyInstance(clazz.classLoader, arrayOf(clazz)) { _, method, args ->
            val realArgs = args?.filter { it !is kotlin.coroutines.Continuation<*> } ?: emptyList()
            val argsStr = realArgs.joinToString(", ")
            invocations.add("${clazz.simpleName}.${method.name}($argsStr)")
            when (method.returnType) {
                java.lang.Boolean.TYPE -> false
                java.lang.Integer.TYPE -> 0
                java.lang.Long.TYPE -> 0L
                List::class.java -> emptyList<Any>()
                else -> Unit
            }
        } as T
    }

    @Test
    fun testClearDomainRulesData() = runBlocking {
        val calls = mutableListOf<String>()
        val blockDao = createProxy(BlockRuleDao::class.java, calls)
        val allowDao = createProxy(AllowRuleDao::class.java, calls)
        val rewriteDao = createProxy(RewriteRuleDao::class.java, calls)
        val cosmeticDao = createProxy(CosmeticRuleDao::class.java, calls)
        val subscriptionDao = createProxy(SubscriptionDao::class.java, calls)

        DataCleanupManager.clearDomainRulesData(
            blockDao = blockDao,
            allowDao = allowDao,
            rewriteDao = rewriteDao,
            cosmeticDao = cosmeticDao,
            subscriptionDao = subscriptionDao
        )

        assertTrue(calls.contains("BlockRuleDao.clearAll()"))
        assertTrue(calls.contains("AllowRuleDao.clearAll()"))
        assertTrue(calls.contains("RewriteRuleDao.clearByTargetTypes([${RewriteTargetType.IPV4}, ${RewriteTargetType.IPV6}])"))
        assertTrue(calls.contains("CosmeticRuleDao.clearAll()"))
        assertTrue(calls.contains("CosmeticRuleDao.clearAllSources()"))
        assertTrue(calls.contains("SubscriptionDao.deleteByKind(${SubscriptionKind.DOMAIN})"))
    }

    @Test
    fun testClearAddressRulesData() = runBlocking {
        val calls = mutableListOf<String>()
        val goUrlDao = createProxy(GoUrlRuleDao::class.java, calls)
        val rewriteDao = createProxy(RewriteRuleDao::class.java, calls)

        DataCleanupManager.clearAddressRulesData(
            goUrlDao = goUrlDao,
            rewriteDao = rewriteDao
        )

        assertTrue(calls.contains("GoUrlRuleDao.clearAll()"))
        assertTrue(calls.contains("RewriteRuleDao.clearByTargetType(${RewriteTargetType.CNAME})"))
        // Address rules cleanup must NOT affect domain rules or subscriptions
        assertFalse(calls.any { it.contains("BlockRuleDao") })
        assertFalse(calls.any { it.contains("SubscriptionDao") })
    }

    @Test
    fun testClearSubscriptionsData() = runBlocking {
        val calls = mutableListOf<String>()
        val subscriptionDao = createProxy(SubscriptionDao::class.java, calls)
        val subscriptionGroupDao = createProxy(SubscriptionGroupDao::class.java, calls)
        val subscriptionAutoUpdateDao = createProxy(SubscriptionAutoUpdateDao::class.java, calls)
        val blockDao = createProxy(BlockRuleDao::class.java, calls)
        val allowDao = createProxy(AllowRuleDao::class.java, calls)
        val rewriteDao = createProxy(RewriteRuleDao::class.java, calls)
        val goUrlDao = createProxy(GoUrlRuleDao::class.java, calls)
        val cosmeticDao = createProxy(CosmeticRuleDao::class.java, calls)

        DataCleanupManager.clearSubscriptionsData(
            subscriptionDao = subscriptionDao,
            subscriptionGroupDao = subscriptionGroupDao,
            subscriptionAutoUpdateDao = subscriptionAutoUpdateDao,
            blockDao = blockDao,
            allowDao = allowDao,
            rewriteDao = rewriteDao,
            goUrlDao = goUrlDao,
            cosmeticDao = cosmeticDao
        )

        assertTrue(calls.contains("SubscriptionDao.clearAll()"))
        assertTrue(calls.contains("SubscriptionGroupDao.clearAll()"))
        assertTrue(calls.contains("SubscriptionAutoUpdateDao.clear()"))
        assertTrue(calls.contains("BlockRuleDao.clearSubscriptionRules()"))
        assertTrue(calls.contains("AllowRuleDao.clearSubscriptionRules()"))
        assertTrue(calls.contains("RewriteRuleDao.clearSubscriptionRules()"))
        assertTrue(calls.contains("GoUrlRuleDao.clearSubscriptionRules()"))
        assertTrue(calls.contains("CosmeticRuleDao.clearSubscriptionRules()"))
    }

    @Test
    fun testDeleteDirectoryContents() {
        val tempDir = Files.createTempDirectory("diting_cleanup_test").toFile()
        try {
            val file1 = File(tempDir, "test1.apk").apply { writeText("apk content") }
            val subDir = File(tempDir, "subfolder").apply { mkdir() }
            val file2 = File(subDir, "nested.tmp").apply { writeText("nested content") }

            assertTrue(file1.exists())
            assertTrue(file2.exists())
            assertTrue(subDir.exists())

            DataCleanupManager.deleteDirectoryContents(tempDir)

            assertTrue("Parent directory should still exist", tempDir.exists())
            assertEquals("Parent directory should be empty", 0, tempDir.listFiles()?.size ?: 0)
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun testDeleteDirectoryContentsEdgeCases() {
        // null directory
        DataCleanupManager.deleteDirectoryContents(null)

        // non-existent directory
        val nonExistent = File(System.getProperty("java.io.tmpdir"), "non_existent_${System.currentTimeMillis()}")
        DataCleanupManager.deleteDirectoryContents(nonExistent)

        // empty directory
        val emptyDir = Files.createTempDirectory("diting_empty_test").toFile()
        try {
            DataCleanupManager.deleteDirectoryContents(emptyDir)
            assertTrue(emptyDir.exists())
            assertEquals(0, emptyDir.listFiles()?.size ?: 0)
        } finally {
            emptyDir.deleteRecursively()
        }
    }
}
