package com.haoze.diting.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.haoze.diting.crash.CrashBreadcrumbs
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.notification.AppNotificationChannels
import com.haoze.diting.notification.NotificationSettingsStore
import com.haoze.diting.notification.VpnMonitorManager
import com.haoze.diting.notification.VpnNotificationBuilder
import com.haoze.diting.notification.VpnSpeedMonitor
import com.haoze.diting.ui.PermissionDisclosureSettings
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.ui.settings.BootstrapDnsSettingsStore
import com.haoze.diting.ui.settings.OutboundProxySettingsStore
import com.haoze.diting.ui.settings.ResolutionSettingsStore
import com.haoze.diting.ui.settings.SystemSettingsStore
import com.haoze.diting.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex

/**
 * VpnService-based unified Go tunnel and full-policy DNS service.
 *
 * All traffic is handled by the Go userspace network stack (tunnel.aar):
 * - IPv4: local 10.0.0.2/30, DNS server 10.0.0.1
 * - IPv6: local fd00:abcd::2/128, DNS server fd00:abcd::1
 * - The TUN interface always carries the global default routes (0.0.0.0/0, ::/0)
 * - Natively supports all DNS resolution strategies: single provider,
 *   primary/backup failover, concurrent racing, and smart prediction
 */
class DnsVpnService : VpnService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val refreshMutex = Mutex()
    private val dbComponents = DnsVpnDatabaseComponents()
    private val tunnelManager = DnsVpnTunnelManager()
    private val ruleSyncManager = DnsVpnRuleSyncManager()
    private val powerOptimizer = DnsVpnPowerOptimizer(this) { tunnelManager.goInspectionTunnel }
    private val networkMonitor = DnsVpnNetworkMonitor(this)
    private val configManager = DnsVpnRuntimeConfigManager(
        context = this,
        scope = serviceScope,
        refreshMutex = refreshMutex,
        tunnelManager = tunnelManager,
        dbComponents = dbComponents,
        onNotificationRefresh = { refreshForegroundNotification() },
        onRestartVpn = { restartVpnLocked() }
    )

    private lateinit var floatingLogOverlay: FloatingLogOverlayController
    private lateinit var speedMonitor: VpnSpeedMonitor

    private var startIntent: Intent? = null
    private var wasStopped = false

    internal fun onOutboundProxyStatus(state: String, message: String) {
        val changed = OutboundProxySettingsStore.setOutboundProxyStatus(this, state, message)
        if (changed) {
            serviceScope.launch {
                refreshForegroundNotification()
            }
        }
    }

    internal fun resolveDomainThroughTunnel(domain: String, ipv4: Boolean): String? =
        tunnelManager.goInspectionTunnel?.resolveDomain(domain, ipv4)

    override fun onCreate() {
        super.onCreate()
        isServiceAlive = true
        activeService = this
        AppNotificationChannels.createAllChannels(this)
        speedMonitor = VpnSpeedMonitor(this)
        floatingLogOverlay = FloatingLogOverlayController(this)

        configManager.loadInitialConfig()

        dbComponents.initialize(
            context = this,
            scope = serviceScope,
            activeDnsCachePolicy = configManager.activeDnsCachePolicy,
            activeDnsLogMode = { configManager.activeDnsLogMode },
            activeLogRetentionDays = { configManager.activeLogRetentionDays },
            isDomainRulesEnabled = { configManager.activeDomainRulesEnabled },
            onBootstrapHealthReset = { tunnelManager.goInspectionTunnel?.resetBootstrapStats() },
            onClearGoDnsCache = { tunnelManager.goInspectionTunnel?.clearDnsCache() }
        )
        dbComponents.onRulesReloaded = {
            if (tunnelManager.vpnInterface != null) {
                tunnelManager.goInspectionTunnel?.let { tunnel ->
                    tunnel.updateRewriteRules()
                    tunnel.pushRuleSnapshot()
                    tunnel.clearDnsCache()
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpn()
            ACTION_REFRESH_NOTIFICATION -> {
                if (::speedMonitor.isInitialized) {
                    if (NotificationSettingsStore.isTrafficSpeedEnabled(this)) {
                        speedMonitor.start(
                            scope = serviceScope,
                            isVpnActive = { tunnelManager.vpnInterface != null },
                            onSpeedChanged = { refreshForegroundNotification() }
                        )
                    } else {
                        speedMonitor.stop()
                    }
                }
                refreshForegroundNotification()
            }
            ACTION_REFRESH_APP_EXCLUSIONS -> configManager.refreshAppExclusions()
            ACTION_REFRESH_APP_ALLOWLIST -> configManager.refreshAppAllowlist()
            ACTION_REFRESH_RUNTIME_CONFIG -> configManager.refreshRuntimeConfig(
                intent.getStringExtra(EXTRA_REFRESH_REASON) ?: "runtime_config"
            )
            ACTION_REFRESH_FLOATING_LOG -> floatingLogOverlay.refreshSettings()
            ACTION_FLOATING_LOG_APP_STATE -> {
                val foreground = intent.getBooleanExtra(EXTRA_APP_FOREGROUND, true)
                SystemSettingsStore.setMainActivityForeground(this, foreground)
                floatingLogOverlay.setAppInForeground(foreground)
            }
            ACTION_SYNC_RULE -> ruleSyncManager.scheduleRuleSync(
                ruleType = intent.getStringExtra(EXTRA_RULE_TYPE).orEmpty(),
                pattern = intent.getStringExtra(EXTRA_RULE_PATTERN).orEmpty(),
                scope = serviceScope,
                refreshMutex = refreshMutex,
                blockListManager = dbComponents.blockListManager,
                allowListManager = dbComponents.allowListManager,
                goInspectionTunnel = tunnelManager.goInspectionTunnel,
                ruleScope = RuleScope.fromStorage(intent.getStringExtra(EXTRA_RULE_SCOPE).orEmpty())
            )
            ACTION_REFRESH_RULE_INDEXES -> ruleSyncManager.refreshRuleIndexes(
                refreshBlock = intent.getBooleanExtra(EXTRA_REFRESH_BLOCK, false),
                refreshAllow = intent.getBooleanExtra(EXTRA_REFRESH_ALLOW, false),
                refreshRewrite = intent.getBooleanExtra(EXTRA_REFRESH_REWRITE, false),
                scope = serviceScope,
                refreshMutex = refreshMutex,
                blockListManager = dbComponents.blockListManager,
                allowListManager = dbComponents.allowListManager,
                rewriteRuleManager = dbComponents.rewriteRuleManager,
                goInspectionTunnel = tunnelManager.goInspectionTunnel,
                ruleScope = RuleScope.fromStorage(intent.getStringExtra(EXTRA_RULE_SCOPE).orEmpty())
            )
            ACTION_SYNC_HTTPS_REQUEST_RULES -> ruleSyncManager.syncHttpsRequestRules(
                scope = serviceScope,
                refreshMutex = refreshMutex,
                goInspectionTunnel = tunnelManager.goInspectionTunnel
            )
            else -> startVpn(intent)
        }
        return START_STICKY
    }

    private fun startVpn(intent: Intent?) {
        if (tunnelManager.vpnInterface != null) {
            DnsVpnStatusNotifier.sendStatusBroadcast(this, true)
            return
        }
        startIntent = intent
        DnsVpnStatusNotifier.setRunningFlag(this, true)

        configManager.activeResolutionMode = ResolutionSettingsStore.getDnsResolutionMode(this)
        CrashBreadcrumbs.record("VPN", "VPN starting, mode=${configManager.activeResolutionMode.name}")
        val providers = DnsVpnProviderResolver.resolveDnsProviders(this, intent)
        configManager.activeProviders = providers

        val inspectionConfigured = AppRulesSettingsStore.isHttpInspectionEnabled(this) &&
            AppRulesSettingsStore.getHttpInspectionAppPackages(this).isNotEmpty()
        val inspectionRequested = inspectionConfigured && tunnelManager.isHttpsInspectionCertificateInstalled(this)
        val blockedPackages = if (AppRulesSettingsStore.isBlockedAppsEnabled(this)) {
            AppRulesSettingsStore.getBlockedAppPackages(this)
        } else {
            emptySet()
        }
        val appAllowlistRules = if (AppRulesSettingsStore.isAppAllowlistEnabled(this)) {
            AppRulesSettingsStore.getAppAllowlistRuleMap(this)
        } else {
            emptyMap()
        }
        val outboundProxyConfig = OutboundProxySettingsStore.getOutboundProxyConfig(this)
        if (outboundProxyConfig.enabled) {
            val validationError = outboundProxyConfig.validationError(this)
            if (validationError != null) {
                Log.e(TAG, "Outbound proxy configuration rejected: $validationError")
                OutboundProxySettingsStore.setOutboundProxyStatus(this, "error", validationError)
                DnsVpnStatusNotifier.setRunningFlag(this, false)
                DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
                stopSelf()
                return
            }
        }
        val activeInspectionPackages = if (inspectionRequested) {
            AppRulesSettingsStore.getHttpInspectionAppPackages(this)
        } else {
            emptySet()
        }

        val proxyPackage = outboundProxyConfig.proxyAppPackage.takeIf { outboundProxyConfig.enabled }
        val vpnInterface = tunnelManager.establishVpnInterface(
            vpnService = this,
            excludedPackages = AppRulesSettingsStore.getExcludedAppPackages(this),
            proxyPackage = proxyPackage,
            bypassLan = SystemSettingsStore.isBypassLanEnabled(this),
            ipv6Mode = SystemSettingsStore.getIpv6Mode(this)
        ) ?: run {
            Log.e(TAG, "Failed to establish VPN")
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            DnsVpnStatusNotifier.setRunningFlag(this, false)
            DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
            stopSelf()
            return
        }

        configManager.activeBootstrapEnabled = BootstrapDnsSettingsStore.isBootstrapEnabled(this)
        configManager.activeBootstrapIps = BootstrapDnsSettingsStore.loadEnabledBootstrapIpEntries(this)
        val started = tunnelManager.startTunnel(
            service = this,
            scope = serviceScope,
            providers = providers,
            resolutionMode = configManager.activeResolutionMode,
            blockResponseMode = configManager.activeBlockResponseMode,
            dynamicBlockResponseConfig = configManager.activeDynamicBlockResponseConfig,
            cachePolicy = configManager.activeDnsCachePolicy,
            bootstrapEnabled = configManager.activeBootstrapEnabled,
            bootstrapIps = configManager.activeBootstrapIps,
            inspectionRequested = inspectionRequested,
            inspectionPackages = activeInspectionPackages,
            blockedPackages = blockedPackages,
            appAllowlistRules = appAllowlistRules,
            outboundProxyConfig = outboundProxyConfig,
            dbComponents = dbComponents
        )
        if (!started) {
            Log.e(TAG, "Go tunnel failed to start")
            DnsVpnStatusNotifier.setRunningFlag(this, false)
            DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
            stopSelf()
            return
        }

        if (SystemSettingsStore.isAppTrafficStatsEnabled(this) || NotificationSettingsStore.isTrafficSpeedEnabled(this)) {
            TrafficStatsManager.start(this, true)
        }
        powerOptimizer.register()
        runCatching {
            startForeground(
                VpnNotificationBuilder.NOTIFICATION_ID_VPN_SERVICE,
                VpnNotificationBuilder.build(this, configManager.activeProviders, configManager.activeResolutionMode)
            )
        }
        speedMonitor.start(
            scope = serviceScope,
            isVpnActive = { tunnelManager.vpnInterface != null },
            onSpeedChanged = { refreshForegroundNotification() }
        )
        floatingLogOverlay.setVpnRunning(true)
        VpnMonitorManager.onVpnStarted(this)
        DnsVpnStatusNotifier.sendStatusBroadcast(this, true)
        networkMonitor.start()

        serviceScope.launch {
            dbComponents.rulesInitializationJob?.join()
            if (tunnelManager.vpnInterface != null) {
                tunnelManager.goInspectionTunnel?.pushRuleSnapshot()
            }
        }
    }

    private fun restartVpnLocked() {
        tunnelManager.stopInspectionDataPlane()
        tunnelManager.disconnectVpnInterface()
        startVpn(startIntent)
    }

    private fun refreshForegroundNotification() {
        if (tunnelManager.vpnInterface != null) {
            runCatching {
                val notification = VpnNotificationBuilder.build(
                    this,
                    configManager.activeProviders,
                    configManager.activeResolutionMode
                )
                NotificationManagerCompat.from(this).notify(
                    VpnNotificationBuilder.NOTIFICATION_ID_VPN_SERVICE,
                    notification
                )
            }
        }
    }

    private fun stopVpn() {
        CrashBreadcrumbs.record("VPN", "stopVpn() called")
        wasStopped = true
        if (::speedMonitor.isInitialized) speedMonitor.stop()
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.setVpnRunning(false)
        powerOptimizer.unregister()
        networkMonitor.stop()
        DnsVpnStatusNotifier.setRunningFlag(this, false)
        tunnelManager.disconnectVpnInterface()
        DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
        tunnelManager.stopInspectionDataPlane()
        // Traffic stats are persisted by TrafficStatsManager.stop() in onDestroy
        // (bounded synchronous flush), so don't trigger it again here.
        dbComponents.flushLoggersBlocking(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        VpnMonitorManager.onVpnStopped(this)
        stopSelf()
    }

    override fun onRevoke() {
        super.onRevoke()
        Log.w(TAG, "VPN permission revoked, stopping service")
        PermissionDisclosureSettings.updateVpnGrant(this, false)
        wasStopped = false
        stopVpn()
    }

    override fun onDestroy() {
        CrashBreadcrumbs.record("VPN", "DnsVpnService onDestroy()")
        if (::speedMonitor.isInitialized) speedMonitor.stop()
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.destroy()
        powerOptimizer.unregister()
        networkMonitor.stop()
        dbComponents.close()
        isServiceAlive = false
        if (activeService === this) activeService = null
        DnsVpnStatusNotifier.setRunningFlag(this, false)
        tunnelManager.disconnectVpnInterface()
        tunnelManager.stopInspectionDataPlane()
        TrafficStatsManager.stop(this)
        dbComponents.flushLoggersBlocking(this)
        serviceScope.cancel()

        if (!wasStopped) {
            DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
            VpnMonitorManager.onVpnStopped(this)
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "DnsVpnService"
        const val ACTION_STOP = DnsVpnIntentFactory.ACTION_STOP
        const val ACTION_REFRESH_APP_EXCLUSIONS = DnsVpnIntentFactory.ACTION_REFRESH_APP_EXCLUSIONS
        const val ACTION_REFRESH_APP_ALLOWLIST = DnsVpnIntentFactory.ACTION_REFRESH_APP_ALLOWLIST
        const val ACTION_REFRESH_RUNTIME_CONFIG = DnsVpnIntentFactory.ACTION_REFRESH_RUNTIME_CONFIG
        const val ACTION_REFRESH_NOTIFICATION = DnsVpnIntentFactory.ACTION_REFRESH_NOTIFICATION
        const val ACTION_REFRESH_FLOATING_LOG = DnsVpnIntentFactory.ACTION_REFRESH_FLOATING_LOG
        const val ACTION_FLOATING_LOG_APP_STATE = DnsVpnIntentFactory.ACTION_FLOATING_LOG_APP_STATE
        const val ACTION_SYNC_RULE = DnsVpnIntentFactory.ACTION_SYNC_RULE
        const val ACTION_REFRESH_RULE_INDEXES = DnsVpnIntentFactory.ACTION_REFRESH_RULE_INDEXES
        const val ACTION_SYNC_HTTPS_REQUEST_RULES = DnsVpnIntentFactory.ACTION_SYNC_HTTPS_REQUEST_RULES
        const val ACTION_VPN_STATUS_CHANGED = DnsVpnIntentFactory.ACTION_VPN_STATUS_CHANGED

        const val EXTRA_VPN_RUNNING = DnsVpnIntentFactory.EXTRA_VPN_RUNNING
        const val EXTRA_REFRESH_REASON = DnsVpnIntentFactory.EXTRA_REFRESH_REASON
        const val EXTRA_RULE_TYPE = DnsVpnIntentFactory.EXTRA_RULE_TYPE
        const val EXTRA_RULE_PATTERN = DnsVpnIntentFactory.EXTRA_RULE_PATTERN
        const val EXTRA_RULE_SCOPE = DnsVpnIntentFactory.EXTRA_RULE_SCOPE
        const val EXTRA_REFRESH_BLOCK = DnsVpnIntentFactory.EXTRA_REFRESH_BLOCK
        const val EXTRA_REFRESH_ALLOW = DnsVpnIntentFactory.EXTRA_REFRESH_ALLOW
        const val EXTRA_REFRESH_REWRITE = DnsVpnIntentFactory.EXTRA_REFRESH_REWRITE
        const val EXTRA_APP_FOREGROUND = DnsVpnIntentFactory.EXTRA_APP_FOREGROUND

        const val EXTRA_DOH_URL = DnsVpnIntentFactory.EXTRA_DOH_URL
        const val EXTRA_DNS_NAME = DnsVpnIntentFactory.EXTRA_DNS_NAME
        const val EXTRA_DNS_PROTOCOL = DnsVpnIntentFactory.EXTRA_DNS_PROTOCOL
        const val EXTRA_DNS_HOST = DnsVpnIntentFactory.EXTRA_DNS_HOST
        const val EXTRA_DNS_PORT = DnsVpnIntentFactory.EXTRA_DNS_PORT

        @Volatile
        private var isServiceAlive = false

        @Volatile
        private var activeService: DnsVpnService? = null

        fun startIntent(
            context: Context,
            provider: DnsProvider? = null
        ): Intent = DnsVpnIntentFactory.startIntent(context, provider)

        fun stopIntent(context: Context): Intent = DnsVpnIntentFactory.stopIntent(context)

        fun refreshRuntimeConfigIntent(
            context: Context,
            reason: String = "runtime_config"
        ): Intent = DnsVpnIntentFactory.refreshRuntimeConfigIntent(context, reason)

        fun syncRuleIntent(
            context: Context,
            ruleType: String,
            pattern: String,
            scope: RuleScope = RuleScope.DNS
        ): Intent = DnsVpnIntentFactory.syncRuleIntent(context, ruleType, pattern, scope)

        fun refreshRuleIndexesIntent(
            context: Context,
            refreshBlock: Boolean,
            refreshAllow: Boolean,
            refreshRewrite: Boolean,
            scope: RuleScope = RuleScope.DNS
        ): Intent = DnsVpnIntentFactory.refreshRuleIndexesIntent(
            context,
            refreshBlock,
            refreshAllow,
            refreshRewrite,
            scope
        )

        fun syncHttpsRequestRulesIntent(context: Context): Intent =
            DnsVpnIntentFactory.syncHttpsRequestRulesIntent(context)

        fun refreshAppExclusionsIntent(context: Context): Intent =
            DnsVpnIntentFactory.refreshAppExclusionsIntent(context)

        fun refreshAppAllowlistIntent(context: Context): Intent =
            DnsVpnIntentFactory.refreshAppAllowlistIntent(context)

        fun refreshNotification(context: Context) {
            if (isRunning(context)) {
                context.startService(
                    Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_NOTIFICATION)
                )
            }
        }

        fun refreshFloatingLogOverlay(context: Context) {
            if (isRunning(context)) {
                context.startService(
                    Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_FLOATING_LOG)
                )
            }
        }

        fun updateFloatingLogAppState(context: Context, foreground: Boolean) {
            SystemSettingsStore.setMainActivityForeground(context, foreground)
            if (isRunning(context)) {
                context.startService(
                    Intent(context, DnsVpnService::class.java)
                        .setAction(ACTION_FLOATING_LOG_APP_STATE)
                        .putExtra(EXTRA_APP_FOREGROUND, foreground)
                )
            }
        }

        fun isRunning(context: Context): Boolean {
            return DnsVpnStatusNotifier.isRunning(context, isServiceAlive)
        }

        fun setRunningFlag(context: Context, running: Boolean) {
            DnsVpnStatusNotifier.setRunningFlag(context, running)
        }

        fun protectSocket(socket: java.net.Socket): Boolean {
            return activeService?.protect(socket) ?: false
        }

        fun protectSocket(fd: Int): Boolean {
            return activeService?.protect(fd) ?: false
        }

        /**
         * Resolves a domain through the running tunnel's DNS decision path.
         * Returns the engine's JSON result, or null when the VPN is not
         * running (no active service).
         */
        fun resolveThroughTunnel(domain: String, ipv4: Boolean): String? =
            activeService?.resolveDomainThroughTunnel(domain, ipv4)
    }
}
