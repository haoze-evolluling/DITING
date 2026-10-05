package com.haoze.diting.ui.settings

import android.content.Context
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.backend.DnsModePreferences
import com.haoze.diting.dnsmode.backend.DnsRuleSettings
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.DynamicBlockResponseConfig
import com.haoze.diting.vpn.SubscriptionAutoUpdateSettings

/**
 * Dispatches rule-management settings reads/writes by dataset. NORMAL delegates
 * to the original AppRulesSettingsStore / SubscriptionAutoUpdateSettings; DNS_MODE
 * reads and writes fully separate values so the two modes never influence
 * each other.
 */
class RuleSettingsAccess(private val dataset: RuleDataset) {

    /** Master switch of domain rule filtering for the dataset. */
    fun isMasterEnabled(context: Context): Boolean = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.isDomainRulesEnabled(context, dataset)
        RuleDataset.DNS_MODE -> DnsModePreferences.loadConfig(context).adBlockEnabled
    }

    fun setMasterEnabled(context: Context, enabled: Boolean) = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.setDomainRulesEnabled(context, enabled, dataset)
        // Route through DnsModeManager so its StateFlow and the running DNS
        // service stay in sync with the persisted preference.
        RuleDataset.DNS_MODE -> DnsModeManager.updateConfig(
            context,
            DnsModePreferences.loadConfig(context).copy(adBlockEnabled = enabled)
        )
    }

    /**
     * Whether URL rules can take effect. URL rules only matter for the VPN
     * mode's traffic inspection, so the DNS and Express datasets always report false and
     * the UI hides URL-related entries.
     */
    fun isAddressRulesOperational(context: Context): Boolean = when (dataset) {
        RuleDataset.NORMAL -> AppRulesSettingsStore.isAddressRulesFullyOperational(context)
        RuleDataset.EXPRESS, RuleDataset.DNS_MODE -> false
    }

    /** The DNS dataset has no preset whitelist, so everything is user-editable. */
    fun isAllowEditDefaultWhitelist(context: Context): Boolean = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.isAllowEditDefaultWhitelist(context, dataset)
        RuleDataset.DNS_MODE -> true
    }

    fun setAllowEditDefaultWhitelist(context: Context, enabled: Boolean) = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.setAllowEditDefaultWhitelist(context, enabled, dataset)
        RuleDataset.DNS_MODE -> Unit
    }

    fun blockResponseMode(context: Context): BlockResponseMode = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.getBlockResponseMode(context, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.blockResponseMode(context)
    }

    fun setBlockResponseMode(context: Context, mode: BlockResponseMode) = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.setBlockResponseMode(context, mode, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.setBlockResponseMode(context, mode)
    }

    fun dynamicBlockResponseConfig(context: Context): DynamicBlockResponseConfig = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.getDynamicBlockResponseConfig(context, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.dynamicBlockResponseConfig(context)
    }

    fun setDynamicBlockResponseConfig(context: Context, config: DynamicBlockResponseConfig) = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> AppRulesSettingsStore.setDynamicBlockResponseConfig(context, config, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.setDynamicBlockResponseConfig(context, config)
    }

    fun autoUpdateEnabled(context: Context): Boolean = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> SubscriptionAutoUpdateSettings.isEnabled(context, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.autoUpdateEnabled(context)
    }

    fun autoUpdateIntervalHours(context: Context): Int = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> SubscriptionAutoUpdateSettings.intervalHours(context, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.autoUpdateIntervalHours(context)
    }

    fun saveAutoUpdate(context: Context, enabled: Boolean, intervalHours: Int) = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.EXPRESS -> SubscriptionAutoUpdateSettings.save(context, enabled, intervalHours, dataset)
        RuleDataset.DNS_MODE -> DnsRuleSettings.saveAutoUpdate(context, enabled, intervalHours)
    }
}
