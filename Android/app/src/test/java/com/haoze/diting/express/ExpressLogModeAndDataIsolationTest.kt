package com.haoze.diting.express

import com.haoze.diting.data.RuleDataset
import com.haoze.diting.express.config.ExpressConfigAdapter
import com.haoze.diting.express.ui.ExpressBottomBarDestination
import com.haoze.diting.ui.BottomBarDestination
import com.haoze.diting.ui.DnsLogMode
import com.haoze.diting.ui.transfer.ImportedSystemSettings
import com.haoze.diting.ui.transfer.TransferConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests verifying log mode mapping, preference file isolation,
 * and system settings transfer sanitization across RuleDatasets.
 */
class ExpressLogModeAndDataIsolationTest {

    @Test
    fun testDnsLogModeStorageValues() {
        assertEquals("all", DnsLogMode.ALL.storageValue)
        assertEquals("blocked_and_errors", DnsLogMode.BLOCKED_AND_ERRORS.storageValue)
        assertEquals("off", DnsLogMode.OFF.storageValue)
    }

    @Test
    fun testDnsLogModeFromStorageValue() {
        assertEquals(DnsLogMode.ALL, DnsLogMode.fromStorageValue("all"))
        assertEquals(DnsLogMode.BLOCKED_AND_ERRORS, DnsLogMode.fromStorageValue("blocked_and_errors"))
        assertEquals(DnsLogMode.OFF, DnsLogMode.fromStorageValue("off"))

        // Unset or invalid values should fall back to OFF
        assertEquals(DnsLogMode.OFF, DnsLogMode.fromStorageValue(null))
        assertEquals(DnsLogMode.OFF, DnsLogMode.fromStorageValue(""))
        assertEquals(DnsLogMode.OFF, DnsLogMode.fromStorageValue("INVALID_MODE"))
    }

    @Test
    fun testDatasetPreferencesIsolation() {
        val expressPrefs = RuleDataset.EXPRESS.prefsName()
        val normalPrefs = RuleDataset.NORMAL.prefsName()
        val dnsModePrefs = RuleDataset.DNS_MODE.prefsName()

        assertEquals("diting_express_prefs", expressPrefs)
        assertEquals("dns_vpn_prefs", normalPrefs)
        assertEquals("diting_dns_mode_prefs", dnsModePrefs)

        assertNotEquals(expressPrefs, normalPrefs)
        assertNotEquals(expressPrefs, dnsModePrefs)
        assertNotEquals(normalPrefs, dnsModePrefs)
    }

    @Test
    fun testExpressConfigAdapterPreservesLogSettings() {
        val originalSettings = ImportedSystemSettings(
            logRetentionDays = 14,
            dnsLogMode = "ALL",
            floatingLogEnabled = true,
            floatingLogPanelSize = 2,
            hideFromRecentsEnabled = true,
            bypassLanEnabled = true,
            appTrafficStatsEnabled = true,
            trafficStatsRetentionDays = 30,
            trafficSpeedEnabled = true
        )
        val originalConfig = TransferConfig(
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
            outboundProxy = null,
            mirrorTemplates = emptyList(),
            subscriptionGroups = emptyList(),
            subscriptions = emptyList(),
            customBlockRules = emptyList(),
            customAllowRules = emptyList(),
            customRewriteDomainRules = emptyList(),
            customRewriteCnameRules = emptyList(),
            customAddressRules = emptyList(),
            excludedApps = emptySet(),
            blockedApps = emptySet(),
            blockedAppsEnabled = false,
            appAllowlistRules = emptyMap(),
            appAllowlistEnabled = false,
            httpInspection = null,
            domainRulesEnabled = true,
            addressRulesEnabled = null,
            encryptedDnsBlockingEnabled = true,
            blockResponseMode = null,
            dynamicBlockResponse = null,
            allowEditDefaultWhitelist = null,
            subscriptionAutoUpdate = null,
            appearance = null,
            systemSettings = originalSettings
        )

        val sanitizedConfig = ExpressConfigAdapter.sanitizeImportConfig(originalConfig)
        val sanitizedSettings = sanitizedConfig.systemSettings

        assertNotNull(sanitizedSettings)
        // Log & floating overlay settings must be preserved for Express mode
        assertEquals(14, sanitizedSettings?.logRetentionDays)
        assertEquals("ALL", sanitizedSettings?.dnsLogMode)
        assertEquals(true, sanitizedSettings?.floatingLogEnabled)
        assertEquals(2, sanitizedSettings?.floatingLogPanelSize)
        assertEquals(true, sanitizedSettings?.hideFromRecentsEnabled)

        // Full tunnel items must be stripped
        assertNull(sanitizedSettings?.bypassLanEnabled)
        assertNull(sanitizedSettings?.appTrafficStatsEnabled)
        assertNull(sanitizedSettings?.trafficStatsRetentionDays)
        assertNull(sanitizedSettings?.trafficSpeedEnabled)
    }

    @Test
    fun testExpressLogDashboardNavigationAvailability() {
        val destination = ExpressBottomBarDestination.fromLegacy(BottomBarDestination.LOG_DASHBOARD)
        assertEquals(ExpressBottomBarDestination.LOG_DASHBOARD, destination)
        assertEquals("log_dashboard", destination?.id)

        // Full-tunnel traffic stats destination must be excluded in Express Mode
        assertNull(ExpressBottomBarDestination.fromLegacy(BottomBarDestination.APP_TRAFFIC_STATS))
    }
}
