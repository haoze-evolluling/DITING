package com.haoze.diting.express

import com.haoze.diting.data.RuleDataset
import com.haoze.diting.vpn.RuleIndexLayout
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
}
