package com.haoze.diting.express

import android.content.Context
import android.util.Log
import com.haoze.diting.data.ExpressRulesDatabase
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.ui.DnsLogMode
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.Ipv6Mode
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.DnsCacheSettingsStore
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.core.rule.AllowListManager
import com.haoze.diting.core.rule.BlockListManager
import com.haoze.diting.core.rule.BlockResponseMode
import com.haoze.diting.core.rule.DefaultWhitelistSeeder
import com.haoze.diting.core.dns.DnsProvider
import com.haoze.diting.core.rule.RewriteRuleManager
import com.haoze.diting.core.rule.RuleIndexLayout
import com.haoze.diting.core.rule.SubscriptionAutoUpdateScheduler
import com.haoze.diting.core.rule.SubscriptionAutoUpdateSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Handles factory default initialization and seeding for Express Mode.
 *
 * Implements physical isolation: zero inheritance from NORMAL mode. Seeds
 * preset whitelist from assets, configures default public DNS provider (AliDNS),
 * initializes default preferences initing_express_prefs, and generates initial
 * trie index in rule-index/express/.
 */
object ExpressDefaultsSeeder {
    private const val TAG = "ExpressDefaultsSeeder"
    const val KEY_EXPRESS_INITIALIZED = "express_initialized"

    fun isInitialized(context: Context): Boolean {
        return context.getSharedPreferences(RuleDataset.EXPRESS.prefsName(), Context.MODE_PRIVATE)
            .getBoolean(KEY_EXPRESS_INITIALIZED, false)
    }

    /**
     * Checks if Express mode data sandbox is initialized. If not, runs initial seeding.
     */
    suspend fun ensureInitialized(context: Context) = withContext(Dispatchers.IO) {
        if (isInitialized(context)) {
            return@withContext
        }
        seedDefaults(context, forceReset = false)
    }

    /**
     * Seeds default data for Express mode or resets it to factory defaults.
     */
    suspend fun seedDefaults(context: Context, forceReset: Boolean = false) = withContext(Dispatchers.IO) {
        val appContext = context.applicationContext
        val db = ExpressRulesDatabase.getInstance(appContext)
        val allowDao = db.allowRuleDao()

        Log.i(TAG, "Initializing factory defaults for Express mode (forceReset=$forceReset)...")

        // 1. Factory preferences
        AppRulesSettingsStore.setDomainRulesEnabled(appContext, true, RuleDataset.EXPRESS)
        AppRulesSettingsStore.setBlockResponseMode(appContext, BlockResponseMode.NXDOMAIN, RuleDataset.EXPRESS)
        ResolutionSettingsStore.setDnsResolutionMode(appContext, DnsResolutionMode.SINGLE, RuleDataset.EXPRESS)
        DnsCacheSettingsStore.setCacheEnabled(appContext, true, RuleDataset.EXPRESS)
        SystemSettingsStore.setDnsLogMode(appContext, DnsLogMode.ALL, RuleDataset.EXPRESS)
        SystemSettingsStore.setIpv6Mode(appContext, Ipv6Mode.AUTO, RuleDataset.EXPRESS)
        SubscriptionAutoUpdateSettings.save(appContext, enabled = true, intervalHours = 24, dataset = RuleDataset.EXPRESS)
        DnsProvider.saveSelected(appContext, "preset_alidns_dns", RuleDataset.EXPRESS)

        // 2. Preset whitelist seeding
        if (forceReset) {
            allowDao.deleteBySource(DefaultWhitelistSeeder.SOURCE_PRESET)
        }
        val entries = DefaultWhitelistSeeder.parseAssetWhitelist(appContext)
        val now = System.currentTimeMillis()
        val entities = entries.map { (domain, category) ->
            AllowRuleEntity(
                pattern = domain,
                rawLine = domain,
                addedAt = now,
                enabled = true,
                groupName = category,
                appScope = null,
                appInverted = false,
                isWildcard = domain.contains('*'),
                important = false
            )
        }
        allowDao.insertAllForSource(entities, DefaultWhitelistSeeder.SOURCE_PRESET, sourceEnabled = true)
        Log.i(TAG, "Seeded ${entities.size} preset whitelist rules in Express DB")

        // 3. Build initial .trie rule index in rule-index/express/
        val ruleIndexDir = RuleIndexLayout.rootDirectory(appContext.filesDir, RuleDataset.EXPRESS)
        ruleIndexDir.mkdirs()
        runCatching {
            AllowListManager(db.allowRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
            BlockListManager(db.blockRuleDao(), ruleIndexDir).refreshCache(forceRebuild = true)
            RewriteRuleManager(db.rewriteRuleDao(), ruleIndexDir).refreshCache(rebuildSubscriptionIndex = true)
        }.onFailure { e ->
            Log.w(TAG, "Initial rule index build encountered error", e)
        }

        // 4. Mark initialized
        appContext.getSharedPreferences(RuleDataset.EXPRESS.prefsName(), Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_EXPRESS_INITIALIZED, true)
            .apply()

        // 5. WorkManager scheduler sync
        SubscriptionAutoUpdateScheduler.sync(appContext, RuleDataset.EXPRESS)
        Log.i(TAG, "Express mode initialized successfully")
    }
}
