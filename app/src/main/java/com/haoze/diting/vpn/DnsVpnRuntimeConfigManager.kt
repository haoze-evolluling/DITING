package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import com.haoze.diting.ui.DnsLogMode
import com.haoze.diting.ui.DnsResolutionMode
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.BootstrapDnsSettingsStore
import com.haoze.diting.ui.settings.DnsCacheSettingsStore
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.vpn.cache.DnsCachePolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Manages active runtime configuration state for [DnsVpnService], including
 * dynamic re-configuration of DNS resolvers, cache policy, and app allowlist/exclusion rules.
 */
class DnsVpnRuntimeConfigManager(
    private val context: Context,
    private val scope: CoroutineScope,
    private val refreshMutex: Mutex,
    private val tunnelManager: DnsVpnTunnelManager,
    private val dbComponents: DnsVpnDatabaseComponents,
    private val onNotificationRefresh: () -> Unit,
    private val onRestartVpn: () -> Unit
) {

    @Volatile
    var activeProviders: List<DnsProvider> = emptyList()

    @Volatile
    var activeResolutionMode: DnsResolutionMode = DnsResolutionMode.SINGLE

    @Volatile
    lateinit var activeDnsCachePolicy: DnsCachePolicy

    @Volatile
    var activeDnsLogMode: DnsLogMode = DnsLogMode.OFF

    @Volatile
    var activeLogRetentionDays: Int = 7

    @Volatile
    var activeBlockResponseMode: BlockResponseMode = BlockResponseMode.NXDOMAIN

    @Volatile
    var activeDynamicBlockResponseConfig: DynamicBlockResponseConfig = DynamicBlockResponseConfig()

    @Volatile
    var activeBootstrapEnabled: Boolean = false

    @Volatile
    var activeBootstrapIps: List<BootstrapIpEntry> = emptyList()

    @Volatile
    var activeDomainRulesEnabled: Boolean = true

    val dynamicBlockResponseTracker = DynamicBlockResponseTracker()

    fun loadInitialConfig() {
        activeLogRetentionDays = SystemSettingsStore.logRetentionDays(context)
        activeDnsCachePolicy = DnsCacheSettingsStore.getDnsCachePolicy(context)
        activeResolutionMode = ResolutionSettingsStore.getDnsResolutionMode(context)
        activeDnsLogMode = SystemSettingsStore.getDnsLogMode(context)
        activeBlockResponseMode = AppRulesSettingsStore.getBlockResponseMode(context)
        activeDynamicBlockResponseConfig = AppRulesSettingsStore.getDynamicBlockResponseConfig(context)
        activeBootstrapEnabled = BootstrapDnsSettingsStore.isBootstrapEnabled(context)
        activeBootstrapIps = BootstrapDnsSettingsStore.loadEnabledBootstrapIpEntries(context)
        activeDomainRulesEnabled = AppRulesSettingsStore.isDomainRulesEnabled(context)
    }

    fun refreshRuntimeConfig(reason: String) {
        if (tunnelManager.vpnInterface == null) {
            Log.d(TAG, "Skip runtime config refresh because VPN is not running: $reason")
            return
        }

        scope.launch {
            refreshMutex.withLock {
                val oldProviders = activeProviders
                val newCachePolicy = DnsCacheSettingsStore.getDnsCachePolicy(context)
                val newResolutionMode = ResolutionSettingsStore.getDnsResolutionMode(context)
                val newBootstrapEnabled = BootstrapDnsSettingsStore.isBootstrapEnabled(context)
                val newBootstrapIps = BootstrapDnsSettingsStore.loadEnabledBootstrapIpEntries(context)
                activeDomainRulesEnabled = AppRulesSettingsStore.isDomainRulesEnabled(context)
                activeDnsLogMode = SystemSettingsStore.getDnsLogMode(context)
                activeLogRetentionDays = SystemSettingsStore.logRetentionDays(context)
                val newBlockResponseMode = AppRulesSettingsStore.getBlockResponseMode(context)
                val newDynamicBlockResponseConfig = AppRulesSettingsStore.getDynamicBlockResponseConfig(context)
                val newProviders = runCatching { DnsVpnProviderResolver.resolveDnsProviders(context, null) }

                newProviders.fold(
                    onSuccess = { updatedProviders ->
                        val goSyncError = tunnelManager.goInspectionTunnel?.let { tunnel ->
                            runCatching {
                                tunnel.syncDnsConfig(
                                    providers = updatedProviders,
                                    resolutionMode = newResolutionMode,
                                    blockResponseMode = newBlockResponseMode,
                                    dynamicBlockResponseConfig = newDynamicBlockResponseConfig,
                                    cachePolicy = newCachePolicy,
                                    bootstrapEnabled = newBootstrapEnabled,
                                    bootstrapIps = newBootstrapIps
                                )
                                tunnel.pushRuleSnapshot()
                            }.exceptionOrNull()
                        }
                        activeDnsCachePolicy = newCachePolicy
                        activeBlockResponseMode = newBlockResponseMode
                        activeDynamicBlockResponseConfig = newDynamicBlockResponseConfig
                        activeBootstrapEnabled = newBootstrapEnabled
                        activeBootstrapIps = newBootstrapIps
                        dynamicBlockResponseTracker.clear()
                        dbComponents.dnsCache.updatePolicy(newCachePolicy)
                        if (goSyncError != null) {
                            onNotificationRefresh()
                            Log.w(TAG, "Failed to refresh Go DNS upstream; keeping current snapshot", goSyncError)
                            return@fold
                        }
                        activeResolutionMode = newResolutionMode
                        activeProviders = updatedProviders
                        onNotificationRefresh()
                        Log.i(
                            TAG,
                            "Runtime config refreshed: $reason, providers=${updatedProviders.size}"
                        )
                    },
                    onFailure = { error ->
                        runCatching {
                            tunnelManager.goInspectionTunnel?.syncDnsConfig(
                                providers = oldProviders,
                                resolutionMode = activeResolutionMode,
                                blockResponseMode = newBlockResponseMode,
                                dynamicBlockResponseConfig = newDynamicBlockResponseConfig,
                                cachePolicy = newCachePolicy,
                                bootstrapEnabled = newBootstrapEnabled,
                                bootstrapIps = newBootstrapIps
                            )
                        }.onFailure { syncError ->
                            Log.w(TAG, "Failed to sync Go DNS response policy", syncError)
                        }
                        activeDnsCachePolicy = newCachePolicy
                        activeResolutionMode = newResolutionMode
                        activeBlockResponseMode = newBlockResponseMode
                        activeDynamicBlockResponseConfig = newDynamicBlockResponseConfig
                        activeBootstrapEnabled = newBootstrapEnabled
                        activeBootstrapIps = newBootstrapIps
                        dynamicBlockResponseTracker.clear()
                        dbComponents.dnsCache.updatePolicy(newCachePolicy)
                        onNotificationRefresh()
                        Log.w(TAG, "Failed to refresh DNS resolvers; keeping current snapshot", error)
                    }
                )

                runCatching { dbComponents.blockListManager.refreshCache() }
                    .onFailure { Log.w(TAG, "Failed to refresh block list cache", it) }
                runCatching { dbComponents.allowListManager.refreshCache() }
                    .onFailure { Log.w(TAG, "Failed to refresh allow list cache", it) }
                runCatching { dbComponents.rewriteRuleManager.refreshCache() }
                    .onSuccess { tunnelManager.goInspectionTunnel?.updateRewriteRules() }
                    .onFailure { Log.w(TAG, "Failed to refresh rewrite rule cache", it) }
                tunnelManager.goInspectionTunnel?.pushRuleSnapshot()
            }
        }
    }

    fun refreshAppExclusions() {
        if (tunnelManager.vpnInterface == null) {
            Log.d(TAG, "Skip application exclusion refresh because VPN is not running")
            return
        }

        scope.launch {
            refreshMutex.withLock {
                onRestartVpn()
            }
        }
    }

    fun refreshAppAllowlist() {
        if (tunnelManager.vpnInterface == null) {
            Log.d(TAG, "Skip application allowlist refresh because VPN is not running")
            return
        }

        scope.launch {
            refreshMutex.withLock {
                val rules = if (AppRulesSettingsStore.isAppAllowlistEnabled(context)) {
                    AppRulesSettingsStore.getAppAllowlistRuleMap(context)
                } else {
                    emptyMap()
                }
                tunnelManager.goInspectionTunnel?.syncAppAllowlist(rules)
            }
        }
    }

    companion object {
        private const val TAG = "DnsVpnRuntimeConfigManager"
    }
}
