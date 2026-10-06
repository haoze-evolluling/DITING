package com.haoze.diting.express

import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.core.rule.RuleIndexLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ExpressDataIsolationTest {

    @Test
    fun testPreferencesIsolation() {
        assertEquals("diting_express_prefs", RuleDataset.EXPRESS.prefsName())
        assertEquals("dns_vpn_prefs", RuleDataset.NORMAL.prefsName())
        assertEquals("diting_dns_mode_prefs", RuleDataset.DNS_MODE.prefsName())

        assertNotEquals(RuleDataset.EXPRESS.prefsName(), RuleDataset.NORMAL.prefsName())
        assertNotEquals(RuleDataset.EXPRESS.prefsName(), RuleDataset.DNS_MODE.prefsName())
    }

    @Test
    fun testRuleIndexDirectoryIsolation() {
        val baseDir = File("/test/files")
        val normalDir = RuleIndexLayout.rootDirectory(baseDir, RuleDataset.NORMAL)
        val expressDir = RuleIndexLayout.rootDirectory(baseDir, RuleDataset.EXPRESS)
        val dnsModeDir = RuleIndexLayout.rootDirectory(baseDir, RuleDataset.DNS_MODE)

        assertEquals(File(baseDir, "rule-index"), normalDir)
        assertEquals(File(baseDir, "rule-index/express"), expressDir)

        assertNotEquals(normalDir.absolutePath, expressDir.absolutePath)
        assertTrue(expressDir.absolutePath.endsWith("express"))
    }

    @Test
    fun testScopeDirectoryIsolation() {
        val baseDir = File("/test/files")
        val normalScopeDir = RuleIndexLayout.scopeDirectory(baseDir, com.haoze.diting.data.entity.RuleScope.DNS, RuleDataset.NORMAL)
        val expressScopeDir = RuleIndexLayout.scopeDirectory(baseDir, com.haoze.diting.data.entity.RuleScope.DNS, RuleDataset.EXPRESS)

        assertEquals(File(baseDir, "rule-index"), normalScopeDir)
        assertEquals(File(baseDir, "rule-index/express"), expressScopeDir)

        assertNotEquals(normalScopeDir.absolutePath, expressScopeDir.absolutePath)
        assertTrue(expressScopeDir.absolutePath.contains("express"))
    }

    @Test
    fun testRuleDatasetValues() {
        val datasets = RuleDataset.entries
        assertEquals(3, datasets.size)
        assertTrue(datasets.contains(RuleDataset.NORMAL))
        assertTrue(datasets.contains(RuleDataset.EXPRESS))
        assertTrue(datasets.contains(RuleDataset.DNS_MODE))
    }

    @Test
    fun testDefaultResolutionModeAlignment() {
        assertEquals("single", com.haoze.diting.ui.DnsResolutionMode.SINGLE.storageValue)
        assertEquals(com.haoze.diting.ui.DnsResolutionMode.SINGLE, com.haoze.diting.ui.DnsResolutionMode.fromStorageValue("single"))
        assertEquals(com.haoze.diting.ui.DnsResolutionMode.SINGLE, com.haoze.diting.ui.DnsResolutionMode.fromStorageValue(null) ?: com.haoze.diting.ui.DnsResolutionMode.SINGLE)
    }
}
