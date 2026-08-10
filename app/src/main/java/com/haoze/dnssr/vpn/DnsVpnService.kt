package com.haoze.dnssr.vpn

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.localizedText
import com.haoze.dnssr.ui.DnsResolutionMode
import com.haoze.dnssr.ui.DnsLogMode
import com.haoze.dnssr.ui.PermissionDisclosureSettings
import com.haoze.dnssr.ui.RaceModeStrategy
import com.haoze.dnssr.vpn.cache.DnsCacheController
import com.haoze.dnssr.vpn.cache.DnsCachePolicy
import com.haoze.dnssr.vpn.cache.DnsCacheResult
import com.haoze.dnssr.vpn.cache.DnsResponseCache
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.selects.onTimeout
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.File
import com.haoze.dnssr.data.entity.RuleScope
import java.io.IOException
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.coroutines.coroutineContext
import kotlin.math.max

/**
 * 基于 VpnService 的加密 DNS 服务。
 *
 * 默认创建仅路由 DNS 的虚拟网卡；启用 HTTP(S) 检查时由 Go 全隧道接管同一 TUN：
 * - IPv4：本机 10.0.0.2/30，DNS 服务器 10.0.0.1
 * - IPv6：本机 fd00:abcd::2/128，DNS 服务器 fd00:abcd::1
 * - DNS-only 模式将 :53 查询交给用户选择的 DNS upstream。
 * - HTTP(S) 检查模式由 Go 用户态网络栈负责 DNS、TCP 与 UDP 转发。
 *
 * 新增能力：
 * - 本地 DNS 缓存（可开关、可配置有效期）。
 * - AdGuard 风格屏蔽列表导入与匹配，命中后返回用户配置的本地响应。
 * - 请求日志与统计（通过 / 已过滤 / 失败）。
 * - 服务真实状态通过本地广播同步给 UI。
 */
class DnsVpnService : VpnService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val outputMutex = Mutex()
    private val refreshMutex = Mutex()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var readJob: Job? = null
    private var inspectionFallbackActive = false
    private var goInspectionTunnel: GoInspectionTunnel? = null
    @Volatile
    private var activeInspectionPackages: Set<String> = emptySet()
    @Volatile
    private var resolvers: List<ActiveDnsResolver> = emptyList()
    private var startIntent: Intent? = null

    internal fun onOutboundProxyStatus(state: String, message: String) {
        AppSettings.setOutboundProxyStatus(this, state, message)
        if (vpnInterface != null) {
            runCatching { startForeground(NOTIFICATION_ID, buildForegroundNotification()) }
        }
    }
    private var wasStopped = false
    private val pendingRuleSyncs = mutableMapOf<RuleScope, MutableMap<String, MutableSet<String>>>()
    private var ruleSyncJob: Job? = null
    private lateinit var floatingLogOverlay: FloatingLogOverlayController

    private lateinit var dnsCache: DnsResponseCache
    private lateinit var blockListManager: BlockListManager
    private lateinit var allowListManager: AllowListManager
    private lateinit var rewriteRuleManager: RewriteRuleManager
    private lateinit var domainPolicy: DomainPolicy
    private lateinit var goUrlRuleManager: GoUrlRuleManager
    private lateinit var dnsLogger: DnsLogger
    private lateinit var httpRequestLogger: HttpRequestLogger
    private lateinit var raceLogger: RaceLogger
    private lateinit var bootstrapLogger: BootstrapLogger
    private lateinit var providerHealthEngine: ProviderHealthEngine
    private lateinit var bootstrapHealthEngine: BootstrapHealthEngine
    private lateinit var bootstrapSelector: BootstrapSelector
    @Volatile
    private lateinit var activeDnsCachePolicy: DnsCachePolicy
    @Volatile
    private var activeRaceModeStrategy: RaceModeStrategy = RaceModeStrategy.SMART_PREDICTION
    @Volatile
    private var activeResolutionMode: DnsResolutionMode = DnsResolutionMode.SINGLE
    @Volatile
    private var activeDnsLogMode: DnsLogMode = DnsLogMode.OFF
    @Volatile
    private var activeBlockResponseMode: BlockResponseMode = BlockResponseMode.NXDOMAIN
    @Volatile
    private var activeDynamicBlockResponseConfig = DynamicBlockResponseConfig()
    private val dynamicBlockResponseTracker = DynamicBlockResponseTracker()

    override fun onCreate() {
        super.onCreate()
        isServiceAlive = true
        createNotificationChannel()
        floatingLogOverlay = FloatingLogOverlayController(this)
        val db = AppDatabase.getInstance(this)
        val logRetentionDays = AppSettings.logRetentionDays(this)
        activeDnsCachePolicy = AppSettings.getDnsCachePolicy(this)
        activeRaceModeStrategy = AppSettings.getRaceModeStrategy(this)
        activeResolutionMode = AppSettings.getDnsResolutionMode(this)
        if (AppSettings.isGoTunnelRequired(this) && !activeResolutionMode.isGoTunnelCompatible()) {
            activeResolutionMode = DnsResolutionMode.SINGLE
            AppSettings.setDnsResolutionMode(this, activeResolutionMode)
        }
        activeDnsLogMode = AppSettings.getDnsLogMode(this)
        activeBlockResponseMode = AppSettings.getBlockResponseMode(this)
        activeDynamicBlockResponseConfig = AppSettings.getDynamicBlockResponseConfig(this)
        dnsCache = DnsResponseCache(db.dnsCacheDao(), activeDnsCachePolicy, serviceScope)
        val ruleIndexDirectory = File(filesDir, "rule-index")
        blockListManager = BlockListManager(db.blockRuleDao(), ruleIndexDirectory)
        allowListManager = AllowListManager(db.allowRuleDao(), ruleIndexDirectory)
        rewriteRuleManager = RewriteRuleManager(db.rewriteRuleDao(), ruleIndexDirectory)
        domainPolicy = DomainPolicy(allowListManager, blockListManager)
        goUrlRuleManager = GoUrlRuleManager(db.goUrlRuleDao())
        dnsLogger = DnsLogger(db.dnsLogDao(), logRetentionDays, serviceScope) { activeDnsLogMode }
        httpRequestLogger = HttpRequestLogger(db.httpRequestLogDao(), logRetentionDays, serviceScope) { activeDnsLogMode }
        raceLogger = RaceLogger(db.raceLogDao(), logRetentionDays, serviceScope)
        bootstrapLogger = BootstrapLogger(db.bootstrapLogDao(), logRetentionDays, serviceScope)
        providerHealthEngine = ProviderHealthEngine(this, serviceScope)
        bootstrapHealthEngine = BootstrapHealthEngine(this, serviceScope)
        bootstrapSelector = BootstrapSelector(
            context = this,
            healthEngine = bootstrapHealthEngine,
            logger = bootstrapLogger,
            protectDatagramSocket = { socket -> protect(socket) }
        )

        // 启动时全量加载屏蔽规则到内存缓存
        serviceScope.launch { blockListManager.refreshCache() }
        serviceScope.launch { allowListManager.refreshCache() }
        serviceScope.launch { rewriteRuleManager.refreshCache() }
        serviceScope.launch {
            DnsCacheController.register(dnsCache)
            dnsCache.warmUp()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpn()
            ACTION_REFRESH_APP_EXCLUSIONS -> refreshAppExclusions()
            ACTION_REFRESH_APP_ALLOWLIST -> refreshAppAllowlist()
            ACTION_REFRESH_RACE_MODE_STRATEGY,
            ACTION_REFRESH_RUNTIME_CONFIG -> refreshRuntimeConfig(
                intent.getStringExtra(EXTRA_REFRESH_REASON)
                    ?: "runtime_config"
            )
            ACTION_REFRESH_NOTIFICATION -> refreshForegroundNotification()
            ACTION_REFRESH_FLOATING_LOG -> floatingLogOverlay.refreshSettings()
            ACTION_FLOATING_LOG_APP_STATE -> {
                val foreground = intent.getBooleanExtra(EXTRA_APP_FOREGROUND, true)
                AppSettings.setMainActivityForeground(this, foreground)
                floatingLogOverlay.setAppInForeground(foreground)
            }
            ACTION_SYNC_RULE -> scheduleRuleSync(
                intent.getStringExtra(EXTRA_RULE_TYPE).orEmpty(),
                intent.getStringExtra(EXTRA_RULE_PATTERN).orEmpty(),
                RuleScope.fromStorage(intent.getStringExtra(EXTRA_RULE_SCOPE).orEmpty())
            )
            ACTION_REFRESH_RULE_INDEXES -> refreshRuleIndexes(
                intent.getBooleanExtra(EXTRA_REFRESH_BLOCK, false),
                intent.getBooleanExtra(EXTRA_REFRESH_ALLOW, false),
                intent.getBooleanExtra(EXTRA_REFRESH_REWRITE, false),
                com.haoze.dnssr.data.entity.RuleScope.fromStorage(
                    intent.getStringExtra(EXTRA_RULE_SCOPE).orEmpty()
                )
            )
            ACTION_SYNC_HTTPS_REQUEST_RULES -> syncHttpsRequestRules()
            else -> startVpn(intent)
        }
        return START_STICKY
    }

    private fun startVpn(intent: Intent?) {
        if (vpnInterface != null) {
            sendStatusBroadcast(true)
            return
        }
        startIntent = intent
        setRunningFlag(this, true)

        activeResolutionMode = normalizeGoTunnelResolutionMode()

        val providers = resolveDnsProviders(intent)
        resolvers = providers.map { provider ->
            ActiveDnsResolver(
                provider = provider,
                resolver = createResolver(provider)
            )
        }

        val inspectionConfigured = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            AppSettings.isHttpInspectionEnabled(this) &&
            AppSettings.getHttpInspectionAppPackages(this).isNotEmpty() &&
            !inspectionFallbackActive
        val inspectionRequested = inspectionConfigured && isHttpsInspectionCertificateInstalled()
        val blockedPackages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            AppSettings.isBlockedAppsEnabled(this)
        ) {
            AppSettings.getBlockedAppPackages(this)
        } else {
            emptySet()
        }
        val appAllowlistPackages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && AppSettings.isAppAllowlistEnabled(this) && AppSettings.getAppAllowlistDomains(this).isNotEmpty()) {
            AppSettings.getAppAllowlistPackages(this)
        } else emptySet()
        val appAllowlistDomains = AppSettings.getAppAllowlistDomains(this)
        val outboundProxyConfig = AppSettings.getOutboundProxyConfig(this)
        if (outboundProxyConfig.enabled) {
            val validationError = outboundProxyConfig.validationError(this)
            if (validationError != null) {
                Log.e(TAG, "Outbound proxy configuration rejected: $validationError")
                AppSettings.setOutboundProxyStatus(this, "error", validationError)
                setRunningFlag(this, false)
                sendStatusBroadcast(false)
                stopSelf()
                return
            }
        }
        val fullTunnelRequested = inspectionRequested || blockedPackages.isNotEmpty() ||
            appAllowlistPackages.isNotEmpty() || outboundProxyConfig.enabled
        activeInspectionPackages = if (inspectionRequested) {
            AppSettings.getHttpInspectionAppPackages(this)
        } else {
            emptySet()
        }
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .addAddress(VPN_ADDRESS_V4, 30)
            .addAddress(VPN_ADDRESS_V6, 128)
            .addDnsServer(DNS_SERVER_V4)
            .addDnsServer(DNS_SERVER_V6)
            .allowFamily(android.system.OsConstants.AF_INET)
            .allowFamily(android.system.OsConstants.AF_INET6)
            .setMtu(1500)

        if (fullTunnelRequested) {
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)
        } else {
            builder.addRoute(DNS_SERVER_V4, 32)
            builder.addRoute(DNS_SERVER_V6, 128)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setBlocking(true)
        }

        val proxyPackage = outboundProxyConfig.proxyAppPackage.takeIf { outboundProxyConfig.enabled }
        (AppSettings.getExcludedAppPackages(this) + packageName + listOfNotNull(proxyPackage)).forEach { excludedPackage ->
            try {
                builder.addDisallowedApplication(excludedPackage)
            } catch (e: Exception) {
                Log.w(TAG, "addDisallowedApplication failed for $excludedPackage", e)
            }
        }

        vpnInterface = builder.establish() ?: run {
            Log.e(TAG, "Failed to establish VPN")
            PermissionDisclosureSettings.updateVpnGrant(this, false)
            setRunningFlag(this, false)
            sendStatusBroadcast(false)
            stopSelf()
            return
        }
        configureLegacyBlockingMode(vpnInterface!!)

        if (fullTunnelRequested) {
            val tunnel = GoInspectionTunnel(
                context = this,
                vpnService = this,
                scope = serviceScope,
                dnsConfig = HttpsDnsConfigSnapshot.create(
                    providers,
                    activeResolutionMode,
                    activeBlockResponseMode,
                    activeDynamicBlockResponseConfig
                ),
                inspectionEnabled = inspectionRequested,
                selectedPackages = activeInspectionPackages,
                blockedPackages = blockedPackages,
                appAllowlistPackages = appAllowlistPackages,
                appAllowlistDomains = appAllowlistDomains,
                dnsPolicy = domainPolicy,
                rewriteRuleManager = rewriteRuleManager,
                goUrlRuleManager = goUrlRuleManager,
                dnsLogger = dnsLogger,
                httpRequestLogger = httpRequestLogger,
                filterHttp3 = AppSettings.isHttp3InspectionEnabled(this),
                blockEncryptedDns = AppSettings.isEncryptedDnsBlockingEnabled(this),
                outboundProxyConfig = outboundProxyConfig
            )
            if (!tunnel.start(vpnInterface!!.fd)) {
                Log.e(TAG, "Go full tunnel failed to start")
                runCatching { vpnInterface?.close() }
                vpnInterface = null
                if (blockedPackages.isNotEmpty() || appAllowlistPackages.isNotEmpty()) {
                    setRunningFlag(this, false)
                    sendStatusBroadcast(false)
                    stopSelf()
                    return
                }
                inspectionFallbackActive = true
                startVpn(intent)
                return
            }
            goInspectionTunnel = tunnel
        }

        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        floatingLogOverlay.setVpnRunning(true)

        stopMonitorService()
        sendStatusBroadcast(true)
        // The Go full-TUN engine owns this descriptor while inspection is active.
        if (!fullTunnelRequested) {
            readJob = serviceScope.launch { packetLoop() }
        }
    }

    /** HTTPS MITM must never start from stale preferences after the system CA is removed. */
    private fun isHttpsInspectionCertificateInstalled(): Boolean {
        val installed = runBlocking(Dispatchers.IO) {
            runCatching { GoInspectionCaManager.isInstalled(this@DnsVpnService) }.getOrDefault(false)
        }
        AppSettings.setHttpsInspectionReady(this, installed)
        if (!installed) {
            AppSettings.setHttpInspectionEnabled(this, false)
        }
        return installed
    }

    private fun configureLegacyBlockingMode(iface: ParcelFileDescriptor) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return
        runCatching {
            val flags = Os.fcntlInt(iface.fileDescriptor, OsConstants.F_GETFL, 0)
            Os.fcntlInt(
                iface.fileDescriptor,
                OsConstants.F_SETFL,
                flags and OsConstants.O_NONBLOCK.inv()
            )
        }.onFailure { error ->
            Log.w(TAG, "Unable to enable blocking TUN reads; using polling fallback", error)
        }
    }

    private fun refreshRuntimeConfig(reason: String) {
        if (vpnInterface == null) {
            Log.d(TAG, "Skip runtime config refresh because VPN is not running: $reason")
            return
        }

        serviceScope.launch {
            refreshMutex.withLock {
                val oldResolvers = resolvers
                val newCachePolicy = AppSettings.getDnsCachePolicy(this@DnsVpnService)
                val newRaceModeStrategy = AppSettings.getRaceModeStrategy(this@DnsVpnService)
                val newResolutionMode = normalizeGoTunnelResolutionMode()
                activeDnsLogMode = AppSettings.getDnsLogMode(this@DnsVpnService)
                val newBlockResponseMode = AppSettings.getBlockResponseMode(this@DnsVpnService)
                val newDynamicBlockResponseConfig = AppSettings.getDynamicBlockResponseConfig(this@DnsVpnService)
                val newResolvers = runCatching {
                    resolveDnsProviders(null).map { provider ->
                        ActiveDnsResolver(
                            provider = provider,
                            resolver = createResolver(provider)
                        )
                    }
                }

                newResolvers.fold(
                    onSuccess = success@{ updatedResolvers ->
                        val goSyncError = goInspectionTunnel?.let { tunnel ->
                            runCatching {
                                tunnel.syncDnsConfig(
                                    providers = updatedResolvers.map { it.provider },
                                    resolutionMode = newResolutionMode,
                                    blockResponseMode = newBlockResponseMode,
                                    dynamicBlockResponseConfig = newDynamicBlockResponseConfig
                                )
                            }.exceptionOrNull()
                        }
                        activeDnsCachePolicy = newCachePolicy
                        activeBlockResponseMode = newBlockResponseMode
                        activeDynamicBlockResponseConfig = newDynamicBlockResponseConfig
                        dynamicBlockResponseTracker.clear()
                        dnsCache.updatePolicy(newCachePolicy)
                        if (goSyncError != null) {
                            closeResolverList(updatedResolvers)
                            startForeground(NOTIFICATION_ID, buildForegroundNotification())
                            Log.w(TAG, "Failed to refresh Go DNS upstream; keeping current snapshot", goSyncError)
                            return@success
                        }
                        activeRaceModeStrategy = newRaceModeStrategy
                        activeResolutionMode = newResolutionMode
                        resolvers = updatedResolvers
                        startForeground(NOTIFICATION_ID, buildForegroundNotification())
                        Log.i(
                            TAG,
                            "Runtime config refreshed: $reason, providers=${updatedResolvers.size}"
                        )
                        serviceScope.launch {
                            delay(OLD_RESOLVER_CLOSE_DELAY_MS)
                            closeResolverList(oldResolvers)
                        }
                    },
                    onFailure = { error ->
                        runCatching {
                            goInspectionTunnel?.syncDnsConfig(
                                providers = oldResolvers.map { it.provider },
                                resolutionMode = activeResolutionMode,
                                blockResponseMode = newBlockResponseMode,
                                dynamicBlockResponseConfig = newDynamicBlockResponseConfig
                            )
                        }.onFailure { syncError ->
                            Log.w(TAG, "Failed to sync Go DNS response policy", syncError)
                        }
                        activeDnsCachePolicy = newCachePolicy
                        activeRaceModeStrategy = newRaceModeStrategy
                        activeResolutionMode = newResolutionMode
                        activeBlockResponseMode = newBlockResponseMode
                        activeDynamicBlockResponseConfig = newDynamicBlockResponseConfig
                        dynamicBlockResponseTracker.clear()
                        dnsCache.updatePolicy(newCachePolicy)
                        startForeground(NOTIFICATION_ID, buildForegroundNotification())
                        Log.w(TAG, "Failed to refresh DNS resolvers; keeping current snapshot", error)
                    }
                )

                runCatching { blockListManager.refreshCache() }
                    .onFailure { Log.w(TAG, "Failed to refresh block list cache", it) }
                runCatching { allowListManager.refreshCache() }
                    .onFailure { Log.w(TAG, "Failed to refresh allow list cache", it) }
                runCatching { rewriteRuleManager.refreshCache() }
                    .onSuccess { goInspectionTunnel?.updateRewriteRules() }
                    .onFailure { Log.w(TAG, "Failed to refresh rewrite rule cache", it) }
            }
        }
    }

    private fun buildForegroundNotification(): Notification {
        val defaultNotificationText = when {
            resolvers.size > 1 -> localizedText(this, "已连接") + " · " +
                localizedText(this, activeResolutionMode.displayName) +
                " " + localizedText(this, "${resolvers.size} 个服务商")
            resolvers.isNotEmpty() -> localizedText(this, "已连接") + " · " + localizedText(this, resolvers.first().provider.name)
            else -> localizedText(this, "已连接")
        }
        val proxyConfig = AppSettings.getOutboundProxyConfig(this)
        val proxyStatus = AppSettings.getOutboundProxyStatus(this)
        val notificationText = when {
            proxyConfig.enabled && proxyStatus.first == "error" ->
                localizedText(this, "出站代理不可用 · ${proxyStatus.second.ifBlank { "连接失败" }}")
            proxyConfig.enabled && proxyStatus.first == "connecting" -> localizedText(this, "正在连接出站代理")
            else -> AppSettings.getNotificationTextRunning(this).ifBlank {
                localizedText(this, defaultNotificationText)
            }
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(notificationText)
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE
                )
            )
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun refreshAppExclusions() {
        if (vpnInterface == null) {
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
        if (vpnInterface == null) {
            Log.d(TAG, "Skip application allowlist refresh because VPN is not running")
            return
        }

        serviceScope.launch {
            refreshMutex.withLock {
                val requiresGoTunnel = AppSettings.isGoTunnelRequired(this@DnsVpnService)
                val tunnel = goInspectionTunnel
                if ((tunnel != null) != requiresGoTunnel) {
                    restartVpnLocked()
                    return@withLock
                }
                tunnel?.syncAppAllowlist(
                    packages = if (AppSettings.isAppAllowlistEnabled(this@DnsVpnService)) {
                        AppSettings.getAppAllowlistPackages(this@DnsVpnService)
                    } else {
                        emptySet()
                    },
                    domains = AppSettings.getAppAllowlistDomains(this@DnsVpnService)
                )
            }
        }
    }

    private fun restartVpnLocked() {
        inspectionFallbackActive = false
        readJob?.cancel()
        readJob = null
        stopInspectionDataPlane()
        closeResolvers()
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        startVpn(startIntent)
    }

    private fun refreshForegroundNotification() {
        if (vpnInterface != null) {
            startForeground(NOTIFICATION_ID, buildForegroundNotification())
        }
    }

    private fun createResolver(provider: DnsProvider): DnsResolver {
        return when (provider.protocol) {
            DnsProtocol.DNS -> PlainDnsResolver(
                vpnService = this,
                host = provider.host,
                port = provider.port,
                bootstrapSelector = bootstrapSelector
            )
            DnsProtocol.DOH -> DohResolver(
                vpnService = this,
                dohUrl = provider.url,
                bootstrapSelector = bootstrapSelector
            )
            DnsProtocol.DOT -> DotResolver(
                vpnService = this,
                host = provider.host,
                port = provider.port,
                bootstrapSelector = bootstrapSelector
            )
        }
    }

    private fun resolveDnsProviders(intent: Intent?): List<DnsProvider> {
        val protocol = DnsProtocol.fromStorage(intent?.getStringExtra(EXTRA_DNS_PROTOCOL))
        val url = intent?.getStringExtra(EXTRA_DOH_URL)
        if (!url.isNullOrBlank()) {
            val name = intent.getStringExtra(EXTRA_DNS_NAME)?.takeIf { it.isNotBlank() } ?: "自定义"
            return listOf(
                DnsProvider(
                    id = runtimeCustomProviderId(url),
                    name = name,
                    protocol = DnsProtocol.DOH,
                    url = url,
                    isPreset = false
                )
            )
        }
        if (protocol == DnsProtocol.DOT || protocol == DnsProtocol.DNS) {
            val host = intent?.getStringExtra(EXTRA_DNS_HOST)
            if (!host.isNullOrBlank()) {
                val port = intent.getIntExtra(EXTRA_DNS_PORT, DnsProvider.DEFAULT_DOT_PORT)
                val name = intent.getStringExtra(EXTRA_DNS_NAME)?.takeIf { it.isNotBlank() } ?: "自定义"
                return listOf(
                    DnsProvider(
                        id = runtimeCustomProviderId("$host:$port"),
                        name = name,
                        protocol = protocol,
                        host = host,
                        port = port,
                        isPreset = false
                    )
                )
            }
        }
        when (AppSettings.getDnsResolutionMode(this)) {
            DnsResolutionMode.SINGLE -> Unit
            DnsResolutionMode.SMART_PREDICTION,
            DnsResolutionMode.PARALLEL_RACE -> {
                val ids = if (AppSettings.getDnsResolutionMode(this) == DnsResolutionMode.SMART_PREDICTION) {
                    AppSettings.getSmartPredictionProviderIds(this)
                } else {
                    AppSettings.getParallelRaceProviderIds(this)
                }
                val raceProviders = DnsProvider.loadRuntimeProviders(this).filter { it.id in ids }
                if (raceProviders.size >= 2) return raceProviders
            }
            DnsResolutionMode.PRIMARY_BACKUP -> {
                val byId = DnsProvider.loadRuntimeProviders(this).associateBy { it.id }
                val ordered = AppSettings.getPrimaryBackupProviderIds(this).mapNotNull(byId::get)
                if (ordered.size >= 2) return ordered
            }
        }
        return listOf(DnsProvider.loadSelected(this))
    }

    private fun scheduleRuleSync(ruleType: String, pattern: String, scope: RuleScope) {
        if (pattern.isBlank() || ruleType !in setOf(RULE_TYPE_BLOCK, RULE_TYPE_ALLOW)) return
        synchronized(pendingRuleSyncs) {
            pendingRuleSyncs
                .getOrPut(scope) { mutableMapOf() }
                .getOrPut(ruleType) { linkedSetOf() }
                .add(pattern)
            ruleSyncJob?.cancel()
            ruleSyncJob = serviceScope.launch {
                val pending = synchronized(pendingRuleSyncs) {
                    pendingRuleSyncs.mapValues { (_, rulesByType) ->
                        rulesByType.mapValues { it.value.toSet() }
                    }.also { pendingRuleSyncs.clear() }
                }
                refreshMutex.withLock {
                    pending.forEach { (_, rulesByType) ->
                        rulesByType[RULE_TYPE_BLOCK].orEmpty().forEach { blockListManager.syncCachedPattern(it) }
                        rulesByType[RULE_TYPE_ALLOW].orEmpty().forEach { allowListManager.syncCachedPattern(it) }
                    }
                }
            }
        }
    }

    private fun refreshRuleIndexes(
        refreshBlock: Boolean,
        refreshAllow: Boolean,
        refreshRewrite: Boolean,
        scope: com.haoze.dnssr.data.entity.RuleScope
    ) {
        serviceScope.launch {
            refreshMutex.withLock {
                val blockManager = blockListManager
                val allowManager = allowListManager
                val rewriteManager = rewriteRuleManager
                if (refreshBlock) runCatching { blockManager.refreshCache() }
                    .onFailure { Log.w(TAG, "Failed to refresh block list cache", it) }
                if (refreshAllow) runCatching { allowManager.refreshCache() }
                    .onFailure { Log.w(TAG, "Failed to refresh allow list cache", it) }
                if (refreshRewrite) runCatching { rewriteManager.refreshCache() }
                    .onSuccess { goInspectionTunnel?.updateRewriteRules() }
                    .onFailure { Log.w(TAG, "Failed to refresh rewrite rule cache", it) }
            }
        }
    }

    private fun syncHttpsRequestRules() {
        serviceScope.launch {
            refreshMutex.withLock {
                runCatching { goInspectionTunnel?.updateRequestRules() }
                    .onFailure { Log.w(TAG, "Failed to refresh HTTPS request rules", it) }
            }
        }
    }

    private fun DnsResolutionMode.isGoTunnelCompatible(): Boolean =
        this == DnsResolutionMode.SINGLE || this == DnsResolutionMode.PRIMARY_BACKUP

    private fun normalizeGoTunnelResolutionMode(): DnsResolutionMode {
        val configured = AppSettings.getDnsResolutionMode(this)
        if (!AppSettings.isGoTunnelRequired(this) || configured.isGoTunnelCompatible()) return configured
        AppSettings.setDnsResolutionMode(this, DnsResolutionMode.SINGLE)
        return DnsResolutionMode.SINGLE
    }

    private fun stopVpn() {
        wasStopped = true
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.setVpnRunning(false)
        setRunningFlag(this, false)
        readJob?.cancel()
        readJob = null
        disconnectVpnInterface()
        sendStatusBroadcast(false)
        stopInspectionDataPlane()
        closeResolvers()
        if (::providerHealthEngine.isInitialized) {
            providerHealthEngine.close()
        }
        if (::bootstrapHealthEngine.isInitialized) {
            bootstrapHealthEngine.close()
        }
        flushLoggersBlocking()
        stopForeground(STOP_FOREGROUND_REMOVE)
        startMonitorService()
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
        if (::floatingLogOverlay.isInitialized) floatingLogOverlay.destroy()
        rewriteRuleManager.close()
        isServiceAlive = false
        setRunningFlag(this, false)
        readJob?.cancel()
        disconnectVpnInterface()
        stopInspectionDataPlane()
        closeResolvers()
        if (::dnsCache.isInitialized) {
            runBlocking { DnsCacheController.unregister(dnsCache) }
        }
        if (::providerHealthEngine.isInitialized) {
            providerHealthEngine.close()
        }
        if (::bootstrapHealthEngine.isInitialized) {
            bootstrapHealthEngine.close()
        }
        flushLoggersBlocking()
        serviceScope.cancel()

        if (!wasStopped) {
            sendStatusBroadcast(false)
            startMonitorService()
        }
        super.onDestroy()
    }

    private suspend fun packetLoop() = coroutineScope {
        val iface = vpnInterface ?: return@coroutineScope
        val input = FileInputStream(iface.fileDescriptor)
        val output = FileOutputStream(iface.fileDescriptor)
        val buffer = ByteBuffer.allocate(BUFFER_SIZE)
        val packetQueue = Channel<DnsPacketWork>(capacity = MAX_QUEUED_DNS_PACKETS)
        val workers = List(dnsWorkerCount()) {
            launch {
                for (work in packetQueue) {
                    handleDnsPacket(work.dnsInfo, work.resolvers, output)
                }
            }
        }

        try {
            while (coroutineContext.isActive) {
                buffer.clear()
                val length = try {
                    input.channel.read(buffer)
                } catch (e: Exception) {
                    if (vpnInterface == null) break
                    delay(READ_ERROR_RETRY_DELAY_MS)
                    continue
                }
                if (length < 0) break
                if (length == 0) {
                    waitForTunPacket(iface)
                    continue
                }

                val dnsInfo = IpUdpPacket.parseDnsPacket(buffer.array(), 0, length)
                if (dnsInfo == null || dnsInfo.destPort != 53) {
                    continue
                }

                val currentResolvers = resolvers
                if (currentResolvers.isEmpty()) {
                    Log.w(TAG, "No DNS resolver configured; skipping DNS packet")
                    continue
                }

                packetQueue.send(DnsPacketWork(dnsInfo, currentResolvers))
            }
        } finally {
            packetQueue.close()
            if (!coroutineContext.isActive) {
                workers.forEach { it.cancel() }
            }
        }
    }

    private suspend fun waitForTunPacket(iface: ParcelFileDescriptor) {
        try {
            val pollFd = StructPollfd().apply {
                fd = iface.fileDescriptor
                events = OsConstants.POLLIN.toShort()
            }
            Os.poll(arrayOf(pollFd), TUN_POLL_TIMEOUT_MS)
        } catch (_: Exception) {
            if (vpnInterface != null) delay(READ_ERROR_RETRY_DELAY_MS)
        }
    }

    private fun dnsWorkerCount(): Int {
        return (Runtime.getRuntime().availableProcessors() * DNS_WORKERS_PER_CPU)
            .coerceIn(MIN_DNS_WORKERS, MAX_DNS_WORKERS)
    }

    private fun stopInspectionDataPlane() {
        goInspectionTunnel?.stop()
        goInspectionTunnel = null
        activeInspectionPackages = emptySet()
    }

    private fun disconnectVpnInterface() {
        goInspectionTunnel?.releaseTun()
        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null
    }

    private suspend fun handleDnsPacket(
        dnsInfo: IpUdpPacket.DnsPacketInfo,
        currentResolvers: List<ActiveDnsResolver>,
        output: FileOutputStream
    ) {
        val query = dnsInfo.dnsPayload
        val question = DnsMessageUtils.extractQuestion(query)
        val qname = question?.name ?: DnsMessageUtils.extractQueryName(query)
        val qtype = question?.type ?: DnsMessageUtils.extractQueryType(query)

        try {
            val rewriteAnswers = qname?.let(rewriteRuleManager::findAnswers).orEmpty()
            if (qname != null && rewriteAnswers.isNotEmpty()) {
                val cname = rewriteAnswers.firstOrNull { it.targetType == com.haoze.dnssr.data.entity.RewriteTargetType.CNAME }
                val response = if (cname != null) DnsMessageUtils.buildCnameRewriteResponse(query, cname.targetValue)
                    else DnsMessageUtils.buildRewriteResponse(query, rewriteAnswers.map { it.targetValue })
                writeResponse(dnsInfo, response, output)
                dnsLogger.log(qname, qtype, LogResult.REWRITTEN, "matched rewrite rule; local response")
                return
            }
            val domainDecision = qname?.let(domainPolicy::evaluate)
            if (qname != null && domainDecision is DomainDecision.Block) {
                val dynamicConfig = activeDynamicBlockResponseConfig
                val blockResponseMode = if (dynamicConfig.enabled) {
                    dynamicBlockResponseTracker.responseModeFor(qname, dynamicConfig)
                } else {
                    activeBlockResponseMode
                }
                val blockResponse = DnsMessageUtils.buildBlockedResponse(query, blockResponseMode)
                writeResponse(dnsInfo, blockResponse, output)
                dnsLogger.log(
                    qname,
                    qtype,
                    LogResult.BLOCKED,
                    "matched block rule; response=${blockResponseMode.storageValue}",
                    blockSubscriptionId = domainDecision.source.subscriptionIdOrNull()
                )
                return
            }

            val cacheResult = if (question != null) {
                dnsCache.resolve(question, query) {
                    if (currentResolvers.size > 1) {
                        when (activeResolutionMode) {
                            DnsResolutionMode.PARALLEL_RACE -> resolveRacing(currentResolvers, query, qname, qtype)
                            DnsResolutionMode.SMART_PREDICTION -> resolveSmartPrediction(currentResolvers, query, qname, qtype)
                            DnsResolutionMode.PRIMARY_BACKUP -> resolvePrimaryBackup(currentResolvers, query, qname, qtype)
                            DnsResolutionMode.SINGLE -> resolveWithHealth(currentResolvers.first(), query)
                        }
                    } else {
                        resolveWithHealth(currentResolvers.first(), query)
                    }
                }
            } else {
                val response = if (currentResolvers.size > 1) {
                    when (activeResolutionMode) {
                        DnsResolutionMode.PARALLEL_RACE -> resolveRacing(currentResolvers, query, qname, qtype)
                        DnsResolutionMode.SMART_PREDICTION -> resolveSmartPrediction(currentResolvers, query, qname, qtype)
                        DnsResolutionMode.PRIMARY_BACKUP -> resolvePrimaryBackup(currentResolvers, query, qname, qtype)
                        DnsResolutionMode.SINGLE -> resolveWithHealth(currentResolvers.first(), query)
                    }
                } else {
                    resolveWithHealth(currentResolvers.first(), query)
                }
                DnsCacheResult(response, cached = false)
            }

            writeResponse(dnsInfo, cacheResult.response, output)
            val message = when {
                domainDecision is DomainDecision.Allow && domainDecision.matchedRule != null -> "matched allow rule"
                cacheResult.stale -> "used expired cache after resolver failure"
                else -> null
            }
            dnsLogger.log(
                qname ?: "?",
                qtype,
                LogResult.PASSED,
                message = dnsPassedMessage(cacheResult.response, message),
                cached = cacheResult.cached
            )
        } catch (e: Exception) {
            Log.w(TAG, "DNS upstream resolve failed", e)
            dnsLogger.log(qname ?: "?", qtype, LogResult.ERROR, e.message)
        }
    }

    /**
     * 同时向多个 DNS resolver 发起查询，返回首个成功的响应。
     * 成功后取消其余未完成的请求；全部失败时抛出异常。
     */
    private suspend fun resolveRacing(
        activeResolvers: List<ActiveDnsResolver>,
        query: ByteArray,
        queryName: String?,
        queryType: Int
    ): ByteArray {
        if (activeResolvers.size == 1) return resolveWithHealth(activeResolvers.first(), query)

        val raceStartedAt = System.nanoTime()
        val result = runCatching { resolveParallel(activeResolvers, query) }
        val elapsedMs = max(1L, (System.nanoTime() - raceStartedAt) / 1_000_000L)
        result.fold(
            onSuccess = { resolution ->
                raceLogger.log(
                    queryName = queryName ?: "?",
                    queryType = queryType,
                    strategy = RaceModeStrategy.BRUTE_FORCE_PARALLEL,
                    providerCount = activeResolvers.size,
                    success = true,
                    elapsedMs = elapsedMs,
                    winnerProvider = resolution.winner.provider,
                    winnerElapsedMs = resolution.winnerElapsedMs
                )
                return resolution.response
            },
            onFailure = { error ->
                raceLogger.log(
                    queryName = queryName ?: "?",
                    queryType = queryType,
                    strategy = RaceModeStrategy.BRUTE_FORCE_PARALLEL,
                    providerCount = activeResolvers.size,
                    success = false,
                    elapsedMs = elapsedMs,
                    message = error.message
                )
                throw error
            }
        )
    }

    private suspend fun resolvePrimaryBackup(
        activeResolvers: List<ActiveDnsResolver>,
        query: ByteArray,
        queryName: String?,
        queryType: Int
    ): ByteArray {
        val startedAt = System.nanoTime()
        var lastError: Throwable? = null
        activeResolvers.forEachIndexed { index, resolver ->
            val outcome = runCatching { resolveWithHealthOutcome(resolver, query) }
            outcome.onSuccess { success ->
                val elapsedMs = max(1L, (System.nanoTime() - startedAt) / 1_000_000L)
                raceLogger.log(
                    queryName = queryName ?: "?",
                    queryType = queryType,
                    strategy = RaceModeStrategy.PRIMARY_BACKUP,
                    providerCount = activeResolvers.size,
                    success = true,
                    elapsedMs = elapsedMs,
                    selectedProvider = activeResolvers.first().provider,
                    winnerProvider = resolver.provider,
                    winnerElapsedMs = success.elapsedMs,
                    fallbackUsed = index > 0,
                    fallbackSuccess = index > 0
                )
                return success.response
            }.onFailure { lastError = it }
        }
        val error = lastError ?: IOException("All DNS upstreams failed")
        raceLogger.log(
            queryName = queryName ?: "?",
            queryType = queryType,
            strategy = RaceModeStrategy.PRIMARY_BACKUP,
            providerCount = activeResolvers.size,
            success = false,
            elapsedMs = max(1L, (System.nanoTime() - startedAt) / 1_000_000L),
            selectedProvider = activeResolvers.firstOrNull()?.provider,
            fallbackUsed = activeResolvers.size > 1,
            message = error.message
        )
        throw error
    }

    private suspend fun resolveParallel(
        activeResolvers: List<ActiveDnsResolver>,
        query: ByteArray
    ): RaceResolution {
        return supervisorScope {
            val deferreds = activeResolvers.mapIndexed { index, resolver ->
                async { index to runCatching { resolveWithHealthOutcome(resolver, query) } }
            }
            try {
                val handled = mutableSetOf<Int>()
                var lastError: Throwable? = null
                while (handled.size < deferreds.size) {
                    val (index, result) = select<Pair<Int, Result<ResolverOutcome>>> {
                        deferreds.forEachIndexed { i, deferred ->
                            if (i !in handled) {
                                deferred.onAwait { it }
                            }
                        }
                    }
                    handled.add(index)
                    result.fold(
                        onSuccess = { outcome ->
                            return@supervisorScope RaceResolution(
                                response = outcome.response,
                                winner = outcome.activeResolver,
                                winnerElapsedMs = outcome.elapsedMs
                            )
                        },
                        onFailure = { e ->
                            lastError = e
                        }
                    )
                }
                throw lastError ?: IOException("All DNS upstreams failed")
            } finally {
                deferreds.forEach { it.cancel() }
            }
        }
    }

    /**
     * 智慧预测模式：按持久化的服务商健康权重优先选择 resolver。
     * 首选 resolver 失败时，剩余 resolver 仍会并行兜底，避免预测失误放大为解析失败。
     */
    private suspend fun resolveSmartPrediction(
        activeResolvers: List<ActiveDnsResolver>,
        query: ByteArray,
        queryName: String?,
        queryType: Int
    ): ByteArray {
        if (activeResolvers.size == 1) return resolveWithHealth(activeResolvers.first(), query)

        val raceStartedAt = System.nanoTime()
        val plan = providerHealthEngine.choosePlan(activeResolvers.map { it.provider })
        val selectedIndex = plan.primaryIndex.takeIf { it in activeResolvers.indices } ?: 0
        val selectedResolver = activeResolvers[selectedIndex]
        val result = runCatching { resolveSmartPredictionPlan(activeResolvers, query, plan.copy(primaryIndex = selectedIndex)) }
        val elapsedMs = max(1L, (System.nanoTime() - raceStartedAt) / 1_000_000L)
        result.fold(
            onSuccess = { resolution ->
                raceLogger.log(
                    queryName = queryName ?: "?",
                    queryType = queryType,
                    strategy = RaceModeStrategy.SMART_PREDICTION,
                    providerCount = activeResolvers.size,
                    success = true,
                    elapsedMs = elapsedMs,
                    selectedProvider = selectedResolver.provider,
                    selectedElapsedMs = resolution.selectedElapsedMs,
                    winnerProvider = resolution.winner.provider,
                    winnerElapsedMs = resolution.winnerElapsedMs,
                    fallbackUsed = resolution.fallbackUsed,
                    fallbackSuccess = resolution.fallbackUsed,
                    message = smartPredictionMessage(
                        exploration = plan.exploration,
                        hedgeMiss = resolution.hedgeMiss
                    )
                )
                return resolution.response
            },
            onFailure = { error ->
                raceLogger.log(
                    queryName = queryName ?: "?",
                    queryType = queryType,
                    strategy = RaceModeStrategy.SMART_PREDICTION,
                    providerCount = activeResolvers.size,
                    success = false,
                    elapsedMs = elapsedMs,
                    selectedProvider = selectedResolver.provider,
                    selectedElapsedMs = null,
                    fallbackUsed = true,
                    message = error.message
                )
                throw error
            }
        )
    }

    private fun String.subscriptionIdOrNull(): Long? {
        return if (startsWith("sub_")) removePrefix("sub_").toLongOrNull() else null
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private suspend fun resolveSmartPredictionPlan(
        activeResolvers: List<ActiveDnsResolver>,
        query: ByteArray,
        plan: ProviderPredictionPlan
    ): SmartPredictionResolution {
        return supervisorScope {
            val primaryIndex = plan.primaryIndex
            val secondaryIndex = plan.secondaryIndex?.takeIf { it in activeResolvers.indices && it != primaryIndex }
            val primaryDeferred = async { runCatching { resolveWithHealthOutcome(activeResolvers[primaryIndex], query) } }

            val earlyEvent = select<SmartPredictionEvent> {
                primaryDeferred.onAwait { result -> SmartPredictionEvent.Completed(result) }
                if (secondaryIndex != null) {
                    onTimeout(plan.hedgeDelayMs) { SmartPredictionEvent.HedgeTimeout }
                }
            }

            when (earlyEvent) {
                is SmartPredictionEvent.Completed -> {
                    earlyEvent.result.getOrNull()?.let { outcome ->
                        return@supervisorScope SmartPredictionResolution(
                            response = outcome.response,
                            winner = outcome.activeResolver,
                            winnerElapsedMs = outcome.elapsedMs,
                            selectedElapsedMs = outcome.elapsedMs,
                            fallbackUsed = false
                        )
                    }
                    val fallbackResolvers = activeResolvers.filterIndexed { index, _ -> index != primaryIndex }
                    if (fallbackResolvers.isEmpty()) {
                        throw earlyEvent.result.exceptionOrNull()
                            ?: IOException("Predicted DNS upstream returned an invalid response")
                    }
                    val fallback = resolveParallel(fallbackResolvers, query)
                    SmartPredictionResolution(
                        response = fallback.response,
                        winner = fallback.winner,
                        winnerElapsedMs = fallback.winnerElapsedMs,
                        selectedElapsedMs = earlyEvent.result.getOrNull()?.elapsedMs,
                        fallbackUsed = true,
                        hedgeMiss = false
                    )
                }

                SmartPredictionEvent.HedgeTimeout -> {
                    val secondary = secondaryIndex
                    if (secondary == null) {
                        val result = primaryDeferred.await()
                        val outcome = result.getOrThrow()
                        return@supervisorScope SmartPredictionResolution(
                            response = outcome.response,
                            winner = outcome.activeResolver,
                            winnerElapsedMs = outcome.elapsedMs,
                            selectedElapsedMs = outcome.elapsedMs,
                            fallbackUsed = false
                        )
                    }

                    val secondaryDeferred = async { runCatching { resolveWithHealthOutcome(activeResolvers[secondary], query) } }
                    val hedgedResult = try {
                        awaitFirstSuccessful(
                            listOf(
                                primaryIndex to primaryDeferred,
                                secondary to secondaryDeferred
                            )
                        )
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        null
                    }
                    hedgedResult?.let { first ->
                        val hedgeMiss = first.index != primaryIndex
                        if (hedgeMiss) {
                            providerHealthEngine.recordHedgeMiss(activeResolvers[primaryIndex].provider.id)
                        }
                        return@supervisorScope SmartPredictionResolution(
                            response = first.outcome.response,
                            winner = first.outcome.activeResolver,
                            winnerElapsedMs = first.outcome.elapsedMs,
                            selectedElapsedMs = if (first.index == primaryIndex) first.outcome.elapsedMs else null,
                            fallbackUsed = hedgeMiss,
                            hedgeMiss = hedgeMiss
                        )
                    }

                    val fallbackResolvers = activeResolvers.filterIndexed { index, _ ->
                        index != primaryIndex && index != secondary
                    }
                    if (fallbackResolvers.isEmpty()) {
                        throw IOException("All predicted DNS upstreams failed")
                    }
                    providerHealthEngine.recordHedgeMiss(activeResolvers[primaryIndex].provider.id)
                    val fallback = resolveParallel(fallbackResolvers, query)
                    SmartPredictionResolution(
                        response = fallback.response,
                        winner = fallback.winner,
                        winnerElapsedMs = fallback.winnerElapsedMs,
                        selectedElapsedMs = null,
                        fallbackUsed = true,
                        hedgeMiss = true
                    )
                }
            }
        }
    }

    private suspend fun awaitFirstSuccessful(
        deferreds: List<Pair<Int, Deferred<Result<ResolverOutcome>>>>
    ): IndexedResolverOutcome {
        val handled = mutableSetOf<Int>()
        var lastError: Throwable? = null
        try {
            while (handled.size < deferreds.size) {
                val (index, result) = select<Pair<Int, Result<ResolverOutcome>>> {
                    deferreds.forEach { (resolverIndex, deferred) ->
                        if (resolverIndex !in handled) {
                            deferred.onAwait { resolverIndex to it }
                        }
                    }
                }
                handled.add(index)
                result.fold(
                    onSuccess = { outcome ->
                        return IndexedResolverOutcome(index, outcome)
                    },
                    onFailure = { error ->
                        lastError = error
                    }
                )
            }
            throw lastError ?: IOException("All DNS upstreams failed")
        } finally {
            deferreds.forEach { (_, deferred) -> deferred.cancel() }
        }
    }

    private suspend fun resolveWithHealth(
        activeResolver: ActiveDnsResolver,
        query: ByteArray
    ): ByteArray {
        return resolveWithHealthOutcome(activeResolver, query).response
    }

    private suspend fun resolveWithHealthOutcome(
        activeResolver: ActiveDnsResolver,
        query: ByteArray
    ): ResolverOutcome {
        val startedAt = System.nanoTime()
        val response = try {
            activeResolver.resolver.resolve(query)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            val elapsedMs = max(1L, (System.nanoTime() - startedAt) / 1_000_000L)
            providerHealthEngine.recordResult(
                providerId = activeResolver.provider.id,
                success = false,
                elapsedMs = elapsedMs
            )
            throw e
        }

        val elapsedMs = max(1L, (System.nanoTime() - startedAt) / 1_000_000L)
        val usable = DnsMessageUtils.isUsableUpstreamResponse(response, query)
        providerHealthEngine.recordResult(
            providerId = activeResolver.provider.id,
            success = usable,
            elapsedMs = elapsedMs
        )
        if (!usable) {
            throw IOException("DNS upstream returned invalid response")
        }
        return ResolverOutcome(activeResolver, response, elapsedMs)
    }

    private fun dnsPassedMessage(response: ByteArray, baseMessage: String?): String? {
        val rcode = DnsMessageUtils.responseCode(response)
        val rcodeMessage = if (rcode != null && rcode != 0) {
            "upstream returned ${DnsMessageUtils.responseCodeLabel(response)}"
        } else {
            null
        }
        return listOfNotNull(baseMessage, rcodeMessage)
            .joinToString(separator = "; ")
            .takeIf { it.isNotEmpty() }
    }

    private suspend fun writeResponse(
        request: IpUdpPacket.DnsPacketInfo,
        response: ByteArray,
        output: FileOutputStream
    ) {
        val responsePacket = IpUdpPacket.buildResponsePacket(request, response)
        outputMutex.withLock {
            output.write(responsePacket)
        }
    }

    private fun sendStatusBroadcast(running: Boolean) {
        sendBroadcast(Intent(ACTION_VPN_STATUS_CHANGED).apply {
            putExtra(EXTRA_VPN_RUNNING, running)
            `package` = packageName
        })
    }

    private fun startMonitorService() {
        if (!AppSettings.isPersistentNotificationEnabled(this) ||
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            stopMonitorService()
            return
        }
        try {
            ContextCompat.startForegroundService(this, VpnMonitorService.startIntent(this))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start VpnMonitorService", e)
        }
    }

    private fun stopMonitorService() {
        try {
            stopService(VpnMonitorService.stopIntent(this))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to stop VpnMonitorService", e)
        }
    }

    private fun runtimeCustomProviderId(url: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(url.trim().toByteArray(Charsets.UTF_8))
        val suffix = digest.take(8).joinToString(separator = "") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
        return "runtime_custom_$suffix"
    }

    private fun smartPredictionMessage(exploration: Boolean, hedgeMiss: Boolean): String? {
        return listOfNotNull(
            "exploration".takeIf { exploration },
            "hedge_miss".takeIf { hedgeMiss }
        ).joinToString(separator = ",").takeIf { it.isNotEmpty() }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                localizedText(this, "谛听 服务"),
                NotificationManager.IMPORTANCE_DEFAULT
            )
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun flushLoggersBlocking() {
        runBlocking {
            flushLoggers()
        }
    }

    private suspend fun flushLoggers() {
        if (::dnsCache.isInitialized) {
            dnsCache.flushPendingWrites()
            dnsCache.flushPendingHits()
        }
        if (::dnsLogger.isInitialized) {
            dnsLogger.flush()
        }
        if (::httpRequestLogger.isInitialized) {
            httpRequestLogger.flush()
        }
        if (::raceLogger.isInitialized) {
            raceLogger.flush()
        }
        if (::bootstrapLogger.isInitialized) {
            bootstrapLogger.flush()
        }
    }

    private fun closeResolvers() {
        closeResolverList(resolvers)
        resolvers = emptyList()
    }

    private fun closeResolverList(resolversToClose: List<ActiveDnsResolver>) {
        resolversToClose.forEach { activeResolver ->
            runCatching { activeResolver.resolver.close() }
        }
    }

    companion object {
        private const val TAG = "DnsVpnService"
        private const val ACTION_STOP = "com.haoze.dnssr.STOP_VPN"
        private const val ACTION_REFRESH_APP_EXCLUSIONS = "com.haoze.dnssr.REFRESH_APP_EXCLUSIONS"
        private const val ACTION_REFRESH_APP_ALLOWLIST = "com.haoze.dnssr.REFRESH_APP_ALLOWLIST"
        private const val ACTION_REFRESH_RACE_MODE_STRATEGY = "com.haoze.dnssr.REFRESH_RACE_MODE_STRATEGY"
        private const val ACTION_REFRESH_RUNTIME_CONFIG = "com.haoze.dnssr.REFRESH_RUNTIME_CONFIG"
        private const val ACTION_REFRESH_NOTIFICATION = "com.haoze.dnssr.REFRESH_NOTIFICATION"
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
        private const val RULE_TYPE_BLOCK = "block"
        private const val RULE_TYPE_ALLOW = "allow"
        private const val CHANNEL_ID = "dns_vpn_channel"
        private const val NOTIFICATION_ID = 1
        private const val VPN_ADDRESS_V4 = "10.0.0.2"
        private const val DNS_SERVER_V4 = "10.0.0.1"
        private const val VPN_ADDRESS_V6 = "fd00:abcd::2"
        private const val DNS_SERVER_V6 = "fd00:abcd::1"
        private const val BUFFER_SIZE = 65535
        private const val TUN_POLL_TIMEOUT_MS = 1_000
        private const val READ_ERROR_RETRY_DELAY_MS = 50L
        private const val OLD_RESOLVER_CLOSE_DELAY_MS = 2_000L
        private const val MIN_DNS_WORKERS = 8
        private const val MAX_DNS_WORKERS = 16
        private const val DNS_WORKERS_PER_CPU = 2
        private const val MAX_QUEUED_DNS_PACKETS = 128
        private const val PREFS_NAME = "dns_vpn_prefs"
        private const val KEY_VPN_RUNNING = "vpn_running"

        const val EXTRA_DOH_URL = "doh_url"
        const val EXTRA_DNS_NAME = "dns_name"
        const val EXTRA_DNS_PROTOCOL = "dns_protocol"
        const val EXTRA_DNS_HOST = "dns_host"
        const val EXTRA_DNS_PORT = "dns_port"

        @Volatile
        private var isServiceAlive = false

        fun startIntent(
            context: android.content.Context,
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

        fun stopIntent(context: android.content.Context): Intent {
            return Intent(context, DnsVpnService::class.java).setAction(ACTION_STOP)
        }

        fun refreshRaceModeStrategyIntent(context: android.content.Context): Intent {
            return refreshRuntimeConfigIntent(context, "race_mode_strategy")
                .setAction(ACTION_REFRESH_RACE_MODE_STRATEGY)
        }

        fun refreshRuntimeConfigIntent(
            context: android.content.Context,
            reason: String = "runtime_config"
        ): Intent {
            return Intent(context, DnsVpnService::class.java)
                .setAction(ACTION_REFRESH_RUNTIME_CONFIG)
                .putExtra(EXTRA_REFRESH_REASON, reason)
        }

        fun syncRuleIntent(
            context: android.content.Context,
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
            context: android.content.Context,
            refreshBlock: Boolean,
            refreshAllow: Boolean,
            refreshRewrite: Boolean,
            scope: com.haoze.dnssr.data.entity.RuleScope = com.haoze.dnssr.data.entity.RuleScope.DNS
        ): Intent = Intent(context, DnsVpnService::class.java)
            .setAction(ACTION_REFRESH_RULE_INDEXES)
            .putExtra(EXTRA_REFRESH_BLOCK, refreshBlock)
            .putExtra(EXTRA_REFRESH_ALLOW, refreshAllow)
            .putExtra(EXTRA_REFRESH_REWRITE, refreshRewrite)
            .putExtra(EXTRA_RULE_SCOPE, scope.storageValue)

        fun syncHttpsRequestRulesIntent(context: android.content.Context): Intent =
            Intent(context, DnsVpnService::class.java).setAction(ACTION_SYNC_HTTPS_REQUEST_RULES)

        fun refreshAppExclusionsIntent(context: android.content.Context): Intent {
            return Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_APP_EXCLUSIONS)
        }

        fun refreshAppAllowlistIntent(context: android.content.Context): Intent {
            return Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_APP_ALLOWLIST)
        }

        fun refreshNotificationIntent(context: android.content.Context): Intent {
            return Intent(context, DnsVpnService::class.java)
                .setAction(ACTION_REFRESH_NOTIFICATION)
        }

        fun refreshFloatingLogOverlay(context: android.content.Context) {
            if (isRunning(context)) {
                context.startService(
                    Intent(context, DnsVpnService::class.java).setAction(ACTION_REFRESH_FLOATING_LOG)
                )
            }
        }

        fun updateFloatingLogAppState(context: android.content.Context, foreground: Boolean) {
            AppSettings.setMainActivityForeground(context, foreground)
            if (isRunning(context)) {
                context.startService(
                    Intent(context, DnsVpnService::class.java)
                        .setAction(ACTION_FLOATING_LOG_APP_STATE)
                        .putExtra(EXTRA_APP_FOREGROUND, foreground)
                )
            }
        }

        fun isRunning(context: android.content.Context): Boolean {
            val flagged = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_VPN_RUNNING, false)
            if (flagged && !isServiceAlive) {
                setRunningFlag(context, false)
                return false
            }
            return flagged
        }

        fun setRunningFlag(context: android.content.Context, running: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_VPN_RUNNING, running)
                .apply()
        }
    }
}

private data class ActiveDnsResolver(
    val provider: DnsProvider,
    val resolver: DnsResolver
)

private data class DnsPacketWork(
    val dnsInfo: IpUdpPacket.DnsPacketInfo,
    val resolvers: List<ActiveDnsResolver>
)

private data class ResolverOutcome(
    val activeResolver: ActiveDnsResolver,
    val response: ByteArray,
    val elapsedMs: Long
)

private data class RaceResolution(
    val response: ByteArray,
    val winner: ActiveDnsResolver,
    val winnerElapsedMs: Long
)

private data class SmartPredictionResolution(
    val response: ByteArray,
    val winner: ActiveDnsResolver,
    val winnerElapsedMs: Long,
    val selectedElapsedMs: Long?,
    val fallbackUsed: Boolean,
    val hedgeMiss: Boolean = false
)

private data class IndexedResolverOutcome(
    val index: Int,
    val outcome: ResolverOutcome
)

private sealed interface SmartPredictionEvent {
    data class Completed(val result: Result<ResolverOutcome>) : SmartPredictionEvent
    data object HedgeTimeout : SmartPredictionEvent
}
