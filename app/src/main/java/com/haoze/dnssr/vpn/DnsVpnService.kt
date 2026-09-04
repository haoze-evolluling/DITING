package com.haoze.dnssr.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.notification.AppNotificationChannels
import com.haoze.dnssr.notification.NotificationSettingsStore
import com.haoze.dnssr.notification.VpnMonitorManager
import com.haoze.dnssr.notification.VpnNotificationBuilder
import com.haoze.dnssr.notification.VpnSpeedMonitor
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.DnsLogMode
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.PermissionDisclosureSettings
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.traffic.TrafficStatsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.haoze.dnssr.ui.Ipv6Mode
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 基于 VpnService 的统一 Go 隧道与全策略 DNS 服务。
 *
 * 全流量网络由 Go 用户态网络栈（tunnel.aar）接管：
 * - IPv4：本机 10.0.0.2/30，DNS 服务器 10.0.0.1
 * - IPv6：本机 fd00:abcd::2/128，DNS 服务器 fd00:abcd::1
 * - TUN 网卡始终配置全局默认路由 (0.0.0.0/0, ::/0)
 * - 原生支持单服务商、主备故障转移、并发竞速与智能预测等全量 DNS 解析策略
 */
class DnsVpnService : VpnService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val refreshMutex = Mutex()
    private val dbComponents = DnsVpnDatabaseComponents()
    private val tunnelManager = DnsVpnTunnelManager()
    private val ruleSyncManager = DnsVpnRuleSyncManager()
    private lateinit var floatingLogOverlay: FloatingLogOverlayController
    private lateinit var speedMonitor: VpnSpeedMonitor

    @Volatile
    private var activeProviders: List<DnsProvider> = emptyList()
    @Volatile
    private var activeResolutionMode: DnsResolutionMode = DnsResolutionMode.SINGLE
    @Volatile
    private lateinit var activeDnsCachePolicy: DnsCachePolicy
    @Volatile
    private var activeDnsLogMode: DnsLogMode = DnsLogMode.OFF
    @Volatile
    private var activeLogRetentionDays: Int = 7
    @Volatile
    private var activeBlockResponseMode: BlockResponseMode = BlockResponseMode.NXDOMAIN
    @Volatile
    private var activeDynamicBlockResponseConfig = DynamicBlockResponseConfig()
    @Volatile
    private var activeBootstrapEnabled: Boolean = false
    @Volatile
    private var activeBootstrapIps: List<BootstrapIpEntry> = emptyList()
    @Volatile
    private var activeDomainRulesEnabled: Boolean = true

    private val dynamicBlockResponseTracker = DynamicBlockResponseTracker()
    private var startIntent: Intent? = null
    private var wasStopped = false
    private var screenStateReceiverRegistered = false

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> onScreenStateChanged(interactive = true)
                Intent.ACTION_SCREEN_OFF -> onScreenStateChanged(interactive = false)
            }
        }
    }

    /**
     * 屏幕状态驱动的息屏功耗优化：
     * - TrafficStatsManager 灭屏暂停快照发布（计数照常累计）；
     * - Go 流量统计 tick 亮屏 1s / 灭屏 10s，聚合期间总量不丢。
     */
    private fun onScreenStateChanged(interactive: Boolean) {
        TrafficStatsManager.setScreenInteractive(interactive)
        tunnelManager.goInspectionTunnel?.setTrafficTickIntervalMs(
            if (interactive) TRAFFIC_TICK_INTERVAL_SCREEN_ON_MS else TRAFFIC_TICK_INTERVAL_SCREEN_OFF_MS
        )
    }

    private fun registerScreenStateReceiver() {
        if (!screenStateReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_SCREEN_ON).apply {
                addAction(Intent.ACTION_SCREEN_OFF)
            }
            runCatching { registerReceiver(screenStateReceiver, filter) }
                .onFailure { Log.w(TAG, "Failed to register screen state receiver", it) }
            screenStateReceiverRegistered = true
        }
        // 每次 VPN 启动都按当前屏幕状态同步一次（含排除列表刷新重建隧道的场景，
        // 新建的 Go tracker 需要正确的初始 tick 间隔）
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        onScreenStateChanged(powerManager?.isInteractive ?: true)
    }

    private fun unregisterScreenStateReceiver() {
        if (!screenStateReceiverRegistered) return
        screenStateReceiverRegistered = false
        runCatching { unregisterReceiver(screenStateReceiver) }
    }

    private var physicalNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkChangeDebounceJob: Job? = null

    private fun registerPhysicalNetworkCallback() {
        if (physicalNetworkCallback != null) return
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                scheduleIpv6AdaptationCheck("network_available")
            }

            override fun onLost(network: Network) {
                scheduleIpv6AdaptationCheck("network_lost")
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                scheduleIpv6AdaptationCheck("link_properties_changed")
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                scheduleIpv6AdaptationCheck("capabilities_changed")
            }
        }

        runCatching {
            cm.registerNetworkCallback(request, callback)
            physicalNetworkCallback = callback
            Log.d(TAG, "Registered physical network callback for dynamic IPv6 adaptation")
        }.onFailure {
            Log.w(TAG, "Failed to register physical network callback", it)
        }
    }

    private fun unregisterPhysicalNetworkCallback() {
        networkChangeDebounceJob?.cancel()
        networkChangeDebounceJob = null
        val callback = physicalNetworkCallback ?: return
        physicalNetworkCallback = null
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        runCatching { cm.unregisterNetworkCallback(callback) }
            .onFailure { Log.w(TAG, "Failed to unregister physical network callback", it) }
    }

    private fun scheduleIpv6AdaptationCheck(reason: String) {
        if (tunnelManager.vpnInterface == null) return
        if (AppSettings.getIpv6Mode(this) != Ipv6Mode.AUTO) return

        networkChangeDebounceJob?.cancel()
        networkChangeDebounceJob = serviceScope.launch {
            delay(1500)
            if (tunnelManager.vpnInterface == null) return@launch
            if (AppSettings.getIpv6Mode(this@DnsVpnService) != Ipv6Mode.AUTO) return@launch

            val physicalIpv6Support = tunnelManager.hasPhysicalIpv6Support(this@DnsVpnService)
            val currentIpv6Active = tunnelManager.isIpv6Active

            if (physicalIpv6Support != currentIpv6Active) {
                Log.i(
                    TAG,
                    "Dynamic IPv6 adaptation triggered by $reason: physicalIpv6Support=$physicalIpv6Support, currentIpv6Active=$currentIpv6Active. Reconnecting VPN."
                )
                refreshMutex.withLock {
                    if (tunnelManager.vpnInterface != null) {
                        restartVpnLocked()
                    }
                }
            }
        }
    }

    internal fun onOutboundProxyStatus(state: String, message: String) {
        AppSettings.setOutboundProxyStatus(this, state, message)
        refreshForegroundNotification()
    }

    override fun onCreate() {
        super.onCreate()
        isServiceAlive = true
        AppNotificationChannels.createAllChannels(this)
        speedMonitor = VpnSpeedMonitor(this)
        floatingLogOverlay = FloatingLogOverlayController(this)

        activeLogRetentionDays = AppSettings.logRetentionDays(this)
        activeDnsCachePolicy = AppSettings.getDnsCachePolicy(this)
        activeResolutionMode = AppSettings.getDnsResolutionMode(this)
        activeDnsLogMode = AppSettings.getDnsLogMode(this)
        activeBlockResponseMode = AppSettings.getBlockResponseMode(this)
        activeDynamicBlockResponseConfig = AppSettings.getDynamicBlockResponseConfig(this)
        activeBootstrapEnabled = AppSettings.isBootstrapEnabled(this)
        activeBootstrapIps = AppSettings.loadEnabledBootstrapIpEntries(this)
        activeDomainRulesEnabled = AppSettings.isDomainRulesEnabled(this)

        dbComponents.initialize(
            context = this,
            scope = serviceScope,
            activeDnsCachePolicy = activeDnsCachePolicy,
            activeDnsLogMode = { activeDnsLogMode },
            activeLogRetentionDays = { activeLogRetentionDays },
            isDomainRulesEnabled = { activeDomainRulesEnabled },
            onBootstrapHealthReset = { tunnelManager.goInspectionTunnel?.resetBootstrapStats() },
            onClearGoDnsCache = { tunnelManager.goInspectionTunnel?.clearDnsCache() }
        )
        dbComponents.onRulesReloaded = {
            if (tunnelManager.vpnInterface != null) {
                tunnelManager.goInspectionTunnel?.let { tunnel ->
                    tunnel.updateRewriteRules()
                    tunnel.pushRuleSnapshot()
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
            ACTION_REFRESH_APP_EXCLUSIONS -> refreshAppExclusions()
            ACTION_REFRESH_APP_ALLOWLIST -> refreshAppAllowlist()
            ACTION_REFRESH_RUNTIME_CONFIG -> refreshRuntimeConfig(
                intent.getStringExtra(EXTRA_REFRESH_REASON) ?: "runtime_config"
            )
            ACTION_REFRESH_FLOATING_LOG -> floatingLogOverlay.refreshSettings()
            ACTION_FLOATING_LOG_APP_STATE -> {
                val foreground = intent.getBooleanExtra(EXTRA_APP_FOREGROUND, true)
                AppSettings.setMainActivityForeground(this, foreground)
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

        activeResolutionMode = AppSettings.getDnsResolutionMode(this)
        val providers = DnsVpnProviderResolver.resolveDnsProviders(this, intent)
        activeProviders = providers

        val inspectionConfigured = AppSettings.isHttpInspectionEnabled(this) &&
            AppSettings.getHttpInspectionAppPackages(this).isNotEmpty()
        val inspectionRequested = inspectionConfigured && tunnelManager.isHttpsInspectionCertificateInstalled(this)
        val blockedPackages = if (AppSettings.isBlockedAppsEnabled(this)) {
            AppSettings.getBlockedAppPackages(this)
        } else {
            emptySet()
        }
        val appAllowlistRules = if (AppSettings.isAppAllowlistEnabled(this)) {
            AppSettings.getAppAllowlistRuleMap(this)
        } else {
            emptyMap()
        }
        val outboundProxyConfig = AppSettings.getOutboundProxyConfig(this)
        if (outboundProxyConfig.enabled) {
            val validationError = outboundProxyConfig.validationError(this)
            if (validationError != null) {
                Log.e(TAG, "Outbound proxy configuration rejected: $validationError")
                AppSettings.setOutboundProxyStatus(this, "error", validationError)
                DnsVpnStatusNotifier.setRunningFlag(this, false)
                DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
                stopSelf()
                return
            }
        }
        val activeInspectionPackages = if (inspectionRequested) {
            AppSettings.getHttpInspectionAppPackages(this)
        } else {
            emptySet()
        }

        val proxyPackage = outboundProxyConfig.proxyAppPackage.takeIf { outboundProxyConfig.enabled }
        val vpnInterface = tunnelManager.establishVpnInterface(
            vpnService = this,
            excludedPackages = AppSettings.getExcludedAppPackages(this),
            proxyPackage = proxyPackage,
            bypassLan = AppSettings.isBypassLanEnabled(this),
            ipv6Mode = AppSettings.getIpv6Mode(this)
        ) ?: run {
            Log.e(TAG, "Failed to establish VPN")
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            DnsVpnStatusNotifier.setRunningFlag(this, false)
            DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
            stopSelf()
            return
        }

        activeBootstrapEnabled = AppSettings.isBootstrapEnabled(this)
        activeBootstrapIps = AppSettings.loadEnabledBootstrapIpEntries(this)
        val started = tunnelManager.startTunnel(
            service = this,
            scope = serviceScope,
            providers = providers,
            resolutionMode = activeResolutionMode,
            blockResponseMode = activeBlockResponseMode,
            dynamicBlockResponseConfig = activeDynamicBlockResponseConfig,
            cachePolicy = activeDnsCachePolicy,
            bootstrapEnabled = activeBootstrapEnabled,
            bootstrapIps = activeBootstrapIps,
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

        if (AppSettings.isAppTrafficStatsEnabled(this) || NotificationSettingsStore.isTrafficSpeedEnabled(this)) {
            TrafficStatsManager.start(this, true)
        }
        registerScreenStateReceiver()
        runCatching {
            startForeground(
                VpnNotificationBuilder.NOTIFICATION_ID_VPN_SERVICE,
                VpnNotificationBuilder.build(this, activeProviders, activeResolutionMode)
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
        registerPhysicalNetworkCallback()

        serviceScope.launch {
            dbComponents.rulesInitializationJob?.join()
            if (tunnelManager.vpnInterface != null) {
                tunnelManager.goInspectionTunnel?.pushRuleSnapshot()
            }
        }
    }

    private fun refreshRuntimeConfig(reason: String) {
        if (tunnelManager.vpnInterface == null) {
            Log.d(TAG, "Skip runtime config refresh because VPN is not running: $reason")
            return
        }

        serviceScope.launch {
            refreshMutex.withLock {
                val oldProviders = activeProviders
                val newCachePolicy = AppSettings.getDnsCachePolicy(this@DnsVpnService)
                val newResolutionMode = AppSettings.getDnsResolutionMode(this@DnsVpnService)
                val newBootstrapEnabled = AppSettings.isBootstrapEnabled(this@DnsVpnService)
                val newBootstrapIps = AppSettings.loadEnabledBootstrapIpEntries(this@DnsVpnService)
                activeDomainRulesEnabled = AppSettings.isDomainRulesEnabled(this@DnsVpnService)
                activeDnsLogMode = AppSettings.getDnsLogMode(this@DnsVpnService)
                activeLogRetentionDays = AppSettings.logRetentionDays(this@DnsVpnService)
                val newBlockResponseMode = AppSettings.getBlockResponseMode(this@DnsVpnService)
                val newDynamicBlockResponseConfig = AppSettings.getDynamicBlockResponseConfig(this@DnsVpnService)
                val newProviders = runCatching { DnsVpnProviderResolver.resolveDnsProviders(this@DnsVpnService, null) }

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
                            refreshForegroundNotification()
                            Log.w(TAG, "Failed to refresh Go DNS upstream; keeping current snapshot", goSyncError)
                            return@fold
                        }
                        activeResolutionMode = newResolutionMode
                        activeProviders = updatedProviders
                        refreshForegroundNotification()
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
                        refreshForegroundNotification()
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
            }
        }
    }

    private fun refreshAppExclusions() {
        if (tunnelManager.vpnInterface == null) {
            Log.d(TAG, "Skip application exclusion refresh because VPN is not running")
            return
        }

        serviceScope.launch {
            refreshMutex.withLock {
                restartVpnLocked()
            }
        }
    }

    private fun refreshAppAllowlist() {
        if (tunnelManager.vpnInterface == null) {
            Log.d(TAG, "Skip application allowlist refresh because VPN is not running")
            return
        }

        serviceScope.launch {
            refreshMutex.withLock {
                val rules = if (AppSettings.isAppAllowlistEnabled(this@DnsVpnService)) {
                    AppSettings.getAppAllowlistRuleMap(this@DnsVpnService)
                } else {
                    emptyMap()
                }
                tunnelManager.goInspectionTunnel?.syncAppAllowlist(rules)
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
                val notification = VpnNotificationBuilder.build(this, activeProviders, activeResolutionMode)
                NotificationManagerCompat.from(this).notify(
                    VpnNotificationBuilder.NOTIFICATION_ID_VPN_SERVICE,
                    notification
                )
            }
        }
    }

    private fun stopVpn() {
        wasStopped = true
        if (::speedMonitor.isInitialized) speedMonitor.stop()
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.setVpnRunning(false)
        unregisterScreenStateReceiver()
        unregisterPhysicalNetworkCallback()
        DnsVpnStatusNotifier.setRunningFlag(this, false)
        tunnelManager.disconnectVpnInterface()
        DnsVpnStatusNotifier.sendStatusBroadcast(this, false)
        tunnelManager.stopInspectionDataPlane()
        // 流量统计落库由 onDestroy 中的 TrafficStatsManager.stop() 统一执行（有界同步），
        // 此处不重复触发
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
        if (::speedMonitor.isInitialized) speedMonitor.stop()
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.destroy()
        unregisterScreenStateReceiver()
        unregisterPhysicalNetworkCallback()
        dbComponents.close()
        isServiceAlive = false
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
        private const val ACTION_STOP = "com.haoze.dnssr.STOP_VPN"

        // Go 流量统计 tick 周期（屏幕状态驱动）：灭屏降频阻止 CPU 深睡被打破
        private const val TRAFFIC_TICK_INTERVAL_SCREEN_ON_MS = 1_000L
        private const val TRAFFIC_TICK_INTERVAL_SCREEN_OFF_MS = 10_000L
        private const val ACTION_REFRESH_APP_EXCLUSIONS = "com.haoze.dnssr.REFRESH_APP_EXCLUSIONS"
        private const val ACTION_REFRESH_APP_ALLOWLIST = "com.haoze.dnssr.REFRESH_APP_ALLOWLIST"
        private const val ACTION_REFRESH_RUNTIME_CONFIG = "com.haoze.dnssr.REFRESH_RUNTIME_CONFIG"
        private const val ACTION_REFRESH_NOTIFICATION = "com.haoze.dnssr.notification.REFRESH_NOTIFICATION"
        private const val ACTION_REFRESH_FLOATING_LOG = "com.haoze.dnssr.REFRESH_FLOATING_LOG"
        private const val ACTION_FLOATING_LOG_APP_STATE = "com.haoze.dnssr.FLOATING_LOG_APP_STATE"
        private const val ACTION_SYNC_RULE = "com.haoze.dnssr.SYNC_RULE"
        private const val ACTION_REFRESH_RULE_INDEXES = "com.haoze.dnssr.REFRESH_RULE_INDEXES"
        private const val ACTION_SYNC_HTTPS_REQUEST_RULES = "com.haoze.dnssr.SYNC_HTTPS_REQUEST_RULES"
        const val ACTION_VPN_STATUS_CHANGED = "com.haoze.dnssr.VPN_STATUS_CHANGED"
        const val EXTRA_VPN_RUNNING = "vpn_running"
        private const val EXTRA_REFRESH_REASON = "refresh_reason"
        private const val EXTRA_RULE_TYPE = "rule_type"
        private const val EXTRA_RULE_PATTERN = "rule_pattern"
        private const val EXTRA_RULE_SCOPE = "rule_scope"
        private const val EXTRA_REFRESH_BLOCK = "refresh_block"
        private const val EXTRA_REFRESH_ALLOW = "refresh_allow"
        private const val EXTRA_REFRESH_REWRITE = "refresh_rewrite"
        private const val EXTRA_APP_FOREGROUND = "app_foreground"

        const val EXTRA_DOH_URL = "doh_url"
        const val EXTRA_DNS_NAME = "dns_name"
        const val EXTRA_DNS_PROTOCOL = "dns_protocol"
        const val EXTRA_DNS_HOST = "dns_host"
        const val EXTRA_DNS_PORT = "dns_port"

        @Volatile
        private var isServiceAlive = false

        fun startIntent(
            context: Context,
            provider: DnsProvider? = null
        ): Intent {
            return Intent(context, DnsVpnService::class.java).apply {
                provider?.let {
                    putExtra(EXTRA_DNS_PROTOCOL, it.protocol.name)
                    if (it.protocol == DnsProtocol.DOH) {
                        putExtra(EXTRA_DOH_URL, it.url)
                    } else {
                        putExtra(EXTRA_DNS_HOST, it.host)
                        putExtra(EXTRA_DNS_PORT, it.port)
                    }
                    putExtra(EXTRA_DNS_NAME, it.name)
                }
            }
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, DnsVpnService::class.java).setAction(ACTION_STOP)
        }

        fun refreshRuntimeConfigIntent(
            context: Context,
            reason: String = "runtime_config"
        ): Intent {
            return Intent(context, DnsVpnService::class.java)
                .setAction(ACTION_REFRESH_RUNTIME_CONFIG)
                .putExtra(EXTRA_REFRESH_REASON, reason)
        }

        fun syncRuleIntent(
            context: Context,
            ruleType: String,
            pattern: String,
            scope: RuleScope = RuleScope.DNS
        ): Intent {
            return Intent(context, DnsVpnService::class.java)
                .setAction(ACTION_SYNC_RULE)
                .putExtra(EXTRA_RULE_TYPE, ruleType)
                .putExtra(EXTRA_RULE_PATTERN, pattern)
                .putExtra(EXTRA_RULE_SCOPE, scope.storageValue)
        }

        fun refreshRuleIndexesIntent(
            context: Context,
            refreshBlock: Boolean,
            refreshAllow: Boolean,
            refreshRewrite: Boolean,
            scope: RuleScope = RuleScope.DNS
        ): Intent = Intent(context, DnsVpnService::class.java)
            .setAction(ACTION_REFRESH_RULE_INDEXES)
            .putExtra(EXTRA_REFRESH_BLOCK, refreshBlock)
            .putExtra(EXTRA_REFRESH_ALLOW, refreshAllow)
            .putExtra(EXTRA_REFRESH_REWRITE, refreshRewrite)
            .putExtra(EXTRA_RULE_SCOPE, scope.storageValue)

        fun syncHttpsRequestRulesIntent(context: Context): Intent =
            Intent(context, DnsVpnService::class.java).setAction(ACTION_SYNC_HTTPS_REQUEST_RULES)

        fun refreshAppExclusionsIntent(context: Context): Intent {
            return Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_APP_EXCLUSIONS)
        }

        fun refreshAppAllowlistIntent(context: Context): Intent {
            return Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_APP_ALLOWLIST)
        }

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
            AppSettings.setMainActivityForeground(context, foreground)
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
    }
}
