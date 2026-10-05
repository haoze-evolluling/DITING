package com.haoze.diting.express

import com.haoze.diting.express.config.ExpressConfigAdapter
import com.haoze.diting.ui.ConfigExportSelection
import com.haoze.diting.ui.transfer.ImportedCustomBlockRule
import com.haoze.diting.ui.transfer.ImportedCustomAllowRule
import com.haoze.diting.ui.transfer.ImportedCustomRewriteRule
import com.haoze.diting.ui.transfer.ImportedCustomUrlRule
import com.haoze.diting.ui.transfer.ImportedHttpInspection
import com.haoze.diting.ui.transfer.ImportedOutboundProxy
import com.haoze.diting.ui.transfer.ImportedSystemSettings
import com.haoze.diting.ui.transfer.TransferConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressConfigAdapterTest {

    @Test
    fun `sanitizeExportSelection clears full tunnel features including custom address rules`() {
        val original = ConfigExportSelection(
            providers = true,
            bootstrapIps = true,
            dnsCache = true,
            outboundProxy = true,
            subscriptions = true,
            customDomainRules = true,
            customRewriteDomainRules = true,
            customRewriteCnameRules = true,
            customAddressRules = true,
            excludedApps = true,
            blockedApps = true,
            appAllowlist = true,
            httpInspection = true,
            appearance = true,
            systemSettings = true
        )

        val sanitized = ExpressConfigAdapter.sanitizeExportSelection(original)

        // Preserved DNS features
        assertTrue(sanitized.providers)
        assertTrue(sanitized.bootstrapIps)
        assertTrue(sanitized.dnsCache)
        assertTrue(sanitized.subscriptions)
        assertTrue(sanitized.customDomainRules)
        assertTrue(sanitized.appearance)
        assertTrue(sanitized.systemSettings)

        // Stripped full-tunnel features
        assertFalse(sanitized.outboundProxy)
        assertFalse(sanitized.customRewriteDomainRules)
        assertFalse(sanitized.customRewriteCnameRules)
        assertFalse(sanitized.customAddressRules)
        assertFalse(sanitized.excludedApps)
        assertFalse(sanitized.blockedApps)
        assertFalse(sanitized.appAllowlist)
        assertFalse(sanitized.httpInspection)
    }

    @Test
    fun `sanitizeImportConfig strips full tunnel components from transfer config`() {
        val original = TransferConfig(
            formatVersion = 9,
            providers = emptyList(),
            selectedProvider = null,
            resolutionMode = null,
            presetDnsService = null,
            homeProviderVisibility = null,
            raceTestDomain = null,
            raceProviderRefs = emptyList(),
            smartPredictionProviderRefs = emptyList(),
            parallelRaceProviderRefs = emptyList(),
            primaryBackupProviderRefs = emptyList(),
            latencyTestProviderRefs = emptyList(),
            bootstrapEnabled = true,
            bootstrapIps = emptyList(),
            bootstrapPresetIds = null,
            dnsCache = null,
            outboundProxy = ImportedOutboundProxy(enabled = true, protocol = "SOCKS5", host = "127.0.0.1", port = 1080),
            mirrorTemplates = emptyList(),
            subscriptionGroups = emptyList(),
            subscriptions = emptyList(),
            customBlockRules = listOf(ImportedCustomBlockRule("ad.com", false, null, false, "||ad.com^")),
            customAllowRules = listOf(ImportedCustomAllowRule("work.com", false, null, false, "@@||work.com^")),
            customRewriteDomainRules = listOf(ImportedCustomRewriteRule("a.com", "A", "1.1.1.1", "|a.com\$dnsrewrite=1.1.1.1")),
            customRewriteCnameRules = listOf(ImportedCustomRewriteRule("c.com", "CNAME", "d.com", "|c.com\$dnsrewrite=d.com")),
            customAddressRules = listOf(ImportedCustomUrlRule("bad-path", "block", "bad-path", true)),
            excludedApps = setOf("com.example.app1"),
            blockedApps = setOf("com.example.app2"),
            blockedAppsEnabled = true,
            appAllowlistRules = mapOf("com.example.app3" to setOf("example.com")),
            appAllowlistEnabled = true,
            httpInspection = ImportedHttpInspection(true),
            domainRulesEnabled = true,
            addressRulesEnabled = true,
            encryptedDnsBlockingEnabled = true,
            blockResponseMode = null,
            dynamicBlockResponse = null,
            allowEditDefaultWhitelist = null,
            subscriptionAutoUpdate = null,
            appearance = null,
            systemSettings = ImportedSystemSettings(
                bypassLanEnabled = true,
                appTrafficStatsEnabled = true,
                trafficStatsRetentionDays = 30,
                trafficSpeedEnabled = true,
                hideFromRecentsEnabled = true
            )
        )

        val sanitized = ExpressConfigAdapter.sanitizeImportConfig(original)

        // DNS features preserved
        assertEquals(1, sanitized.customBlockRules.size)
        assertEquals(1, sanitized.customAllowRules.size)
        assertEquals(true, sanitized.systemSettings?.hideFromRecentsEnabled)

        // Full tunnel items stripped
        assertNull(sanitized.outboundProxy)
        assertNull(sanitized.httpInspection)
        assertTrue(sanitized.customRewriteDomainRules.isEmpty())
        assertTrue(sanitized.customRewriteCnameRules.isEmpty())
        assertTrue(sanitized.customAddressRules.isEmpty())
        assertNull(sanitized.addressRulesEnabled)
        assertEquals(emptySet<String>(), sanitized.excludedApps)
        assertEquals(emptySet<String>(), sanitized.blockedApps)
        assertEquals(emptyMap<String, Set<String>>(), sanitized.appAllowlistRules)
        assertFalse(sanitized.appAllowlistEnabled)
        assertNull(sanitized.systemSettings?.bypassLanEnabled)
        assertNull(sanitized.systemSettings?.appTrafficStatsEnabled)
        assertNull(sanitized.systemSettings?.trafficStatsRetentionDays)
        assertNull(sanitized.systemSettings?.trafficSpeedEnabled)
    }
}
