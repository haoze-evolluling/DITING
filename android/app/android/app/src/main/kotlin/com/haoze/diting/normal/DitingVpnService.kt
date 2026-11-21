package com.haoze.diting.normal

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.engine.Engine
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.StorageGate
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.overlay.FloatingLogOverlay
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.UnderlyingNetworkMonitor
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.vpn.VpnServiceForeground
import com.haoze.diting.vpn.applyTo
import com.haoze.diting.watchdog.VpnReclaimer

class DitingVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var engine: Engine? = null
    private var dataPlane: EngineDataPlane? = null
    private var networkMonitor: UnderlyingNetworkMonitor? = null

    @Volatile
    private var worker: Thread? = null

    @Volatile
    private var stopping = false

    private val mainHandler = Handler(Looper.getMainLooper())

    private var tunnelGeneration = 0

    private val speedTicker = SpeedTicker(
        context = this,
        active = { isRunning && !stopping },
        onTick = { VpnNotification.refresh(this, CHANNEL_ID, NOTIFICATION_ID, ACTION_STOP) },
    )

    private val reclaimer = VpnReclaimer(
        service = this,
        workMode = "normal",
        modeTitle = "普通模式",
        channelId = CHANNEL_ID,
        notificationId = NOTIFICATION_ID,
        stopIntent = { stopIntent(this) },
        restoreIntent = { restoreIntent(this) },
        onWaitingChanged = { reclaiming = it },
        onGiveUp = { stopTunnel() },
    )

    override fun onCreate() {
        super.onCreate()
        RuntimeEventLog.info("vpn", "service.create")
        VpnServiceForeground.createChannel(this, CHANNEL_ID, "VPN 服务", "保持 VPN 隧道运行")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        if (intent?.action == ACTION_RELOAD_RULES) {
            reloadRules()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            stopTunnel()
            return START_NOT_STICKY
        }
        if (StorageGate.blocksDataPlane(this)) {
            Log.w(TAG, "storage upgrade in progress; refusing to start")
            stopSelf(startId)
            return START_NOT_STICKY
        }
        reclaimer.cancel()
        val dnsConfig = intent?.getStringExtra(EXTRA_DNS_CONFIG)
        if (dnsConfig.isNullOrBlank()) {
            Log.w(TAG, "start intent without DNS config")
            RuntimeEventLog.warn("vpn", "start.no_config")
            stopTunnel()
            return START_NOT_STICKY
        }
        val defaults = VpnPlanNative.startDefaults
        val proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty()
        val proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty()
        val bypassLan = intent.getBooleanExtra(EXTRA_BYPASS_LAN, defaults.bypassLan)
        val ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: defaults.ipv6Mode
        val excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet()
        val blockedPackages = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES).orEmpty().toSet()
        val inspectionPackages = intent.getStringArrayListExtra(EXTRA_INSPECTION_PACKAGES).orEmpty().toSet()
        val inspectionEnabled =
            intent.getBooleanExtra(EXTRA_INSPECTION_ENABLED, defaults.inspectionEnabled)
        VpnStartConfig.remember(
            context = this,
            dnsConfig = dnsConfig,
            proxyJson = proxyJson,
            proxyAppPackage = proxyAppPackage,
            bypassLan = bypassLan,
            ipv6Mode = ipv6Mode,
            excludedPackages = excludedPackages,
            blockedPackages = blockedPackages,
            inspectionPackages = inspectionPackages,
            inspectionEnabled = inspectionEnabled,
        )
        startTunnel(
            dnsConfig = dnsConfig,
            proxyJson = proxyJson,
            proxyAppPackage = proxyAppPackage,
            bypassLan = bypassLan,
            ipv6Mode = ipv6Mode,
            excludedPackages = excludedPackages,
            blockedPackages = blockedPackages,
            inspectionPackages = inspectionPackages,
            inspectionEnabled = inspectionEnabled,
        )
        return START_NOT_STICKY
    }

    @Synchronized
    private fun startTunnel(
        dnsConfig: String,
        proxyJson: String,
        proxyAppPackage: String,
        bypassLan: Boolean,
        ipv6Mode: String,
        excludedPackages: Set<String>,
        blockedPackages: Set<String>,
        inspectionPackages: Set<String>,
        inspectionEnabled: Boolean,
    ) {
        if (engine != null) {
            Log.i(TAG, "tunnel already running; ignoring duplicate start")
            return
        }
        tunnelGeneration++
        stopping = false
        lastError = null

        val (pfd, ipv6Enabled) = VpnRouteConfig.establish(
            service = this,
            excludedPackages = excludedPackages,
            proxyPackage = proxyAppPackage.ifBlank { null },
            bypassLan = bypassLan,
            ipv6Mode = ipv6Mode,
        )
        if (pfd == null) {
            fail("无法建立 VPN 接口")
            return
        }
        tun = pfd

        val rustEngine = try {
            Engine()
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to load the engine", t)
            RuntimeEventLog.error("vpn", "engine.load_fail", "error" to (t.message ?: t.javaClass.simpleName))
            releaseResources()
            fail("引擎加载失败：${t.message ?: t.javaClass.simpleName}")
            return
        }
        engine = rustEngine
        activeEngine = rustEngine

        try {
            val logMode = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
                ?: DnsLogWriter.MODE_ALL
            val httpsBypassRules = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getStringSet(KEY_HTTPS_BYPASS_RULES, null)
                .orEmpty()
            dataPlane = NormalEngineConfig.configure(
                service = this,
                engine = rustEngine,
                dnsConfig = dnsConfig,
                proxyJson = proxyJson,
                ipv6Enabled = ipv6Enabled,
                blockedPackages = blockedPackages,
                inspectionPackages = inspectionPackages,
                inspectionEnabled = inspectionEnabled,
                logMode = logMode,
                httpsBypassRules = httpsBypassRules,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to configure the engine", t)
            RuntimeEventLog.error("vpn", "engine.config_fail", "error" to (t.message ?: t.javaClass.simpleName))
            releaseResources()
            fail("隧道配置失败：${t.message ?: t.javaClass.simpleName}")
            return
        }

        networkMonitor = UnderlyingNetworkMonitor(this, this) { state ->
            state.applyTo(rustEngine, ipv6Mode)
        }.also { it.start() }

        isRunning = true
        startedAt = System.currentTimeMillis()
        setPersistedRunning(this, true)
        speedTicker.start()
        FloatingLogOverlay.setVpnRunning(this, true)
        LogRetention.start(
            context = this,
            databaseName = RuleDataset.NORMAL.logsDatabase(),
            prefsName = LOG_PREFS,
            includeHttpAndTraffic = true,
        )
        worker = NormalTunnelRunner.start(
            service = this,
            engine = rustEngine,
            tunFd = pfd.fd,
            isStopping = { stopping },
            onFatal = { fail(it) },
        )
    }

    private fun reloadRules() {
        val current = engine
        if (current == null || !isRunning) {
            Log.i(TAG, "rule reload requested but the tunnel is not running")
            return
        }
        NormalTunnelRunner.reload(this, current)
    }

    @Synchronized
    private fun stopTunnel() {
        reclaimer.cancel()
        stopping = true
        val generation = tunnelGeneration
        val current = engine
        val plane = dataPlane
        val currentTun = tun
        engine = null
        activeEngine = null
        dataPlane = null
        tun = null
        isRunning = false
        startedAt = 0L
        FloatingLogOverlay.setVpnRunning(this, false)
        Thread({
            releaseTunnel(current, plane)
            runCatching { currentTun?.close() }
            mainHandler.post {
                if (generation != tunnelGeneration) return@post
                releaseResources()
                setPersistedRunning(this@DitingVpnService, false)
                VpnServiceForeground.stop(this@DitingVpnService)
                stopSelf()
            }
        }, "diting-teardown").start()
    }

    @Synchronized
    private fun teardown() {
        stopping = true
        val current = engine
        val plane = dataPlane
        engine = null
        activeEngine = null
        dataPlane = null
        releaseTunnel(current, plane)
        releaseResources()
        isRunning = false
        startedAt = 0L
        FloatingLogOverlay.setVpnRunning(this, false)
    }

    private fun releaseTunnel(engine: Engine?, plane: EngineDataPlane?) {
        runCatching { engine?.stop() }
            .onFailure { Log.w(TAG, "engine.stop failed", it) }
        runCatching { engine?.stopStackMitm() }
        runCatching { engine?.releaseTun() }
        runCatching { plane?.close() }
    }

    private fun closeDataPlane() {
        val plane = dataPlane
        dataPlane = null
        runCatching { plane?.close() }
    }

    private fun releaseResources() {
        networkMonitor?.stop()
        networkMonitor = null
        runCatching { tun?.close() }
        tun = null
        worker = null
        speedTicker.stop()
        FloatingLogOverlay.setVpnRunning(this, false)
        TrafficRateMonitor.reset()
        LogRetention.stop()
    }

    private fun fail(message: String) {
        RuntimeEventLog.error("vpn", "tunnel.fail", "message" to message)
        lastError = message
        isRunning = false
        startedAt = 0L
        activeEngine = null
        closeDataPlane()
        setPersistedRunning(this, false)
        releaseResources()
        VpnServiceForeground.stop(this)
        stopSelf()
    }

    override fun onRevoke() {
        RuntimeEventLog.warn("vpn", "revoked")
        if (reclaimer.shouldFollow()) {
            Log.w(TAG, "VPN revoked; waiting for the slot to free up")
            teardown()
            QuickSettingsTileUpdater.requestTileUpdate(this)
            reclaimer.begin()
            return
        }
        Log.w(TAG, "VPN permission revoked")
        stopTunnel()
        super.onRevoke()
    }

    override fun onDestroy() {
        RuntimeEventLog.info("vpn", "service.destroy")
        reclaimer.cancel()
        if (engine != null || isRunning || dataPlane != null) {
            teardown()
            setPersistedRunning(this, false)
            VpnServiceForeground.stop(this)
        }
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val error = VpnServiceForeground.promote(
            this,
            NOTIFICATION_ID,
            VpnNotification.build(this, CHANNEL_ID, ACTION_STOP),
        ) ?: return
        Log.e(TAG, "startForeground failed", error)
        RuntimeEventLog.error("vpn", "foreground.fail", "error" to (error.message ?: error.javaClass.simpleName))
    }

    companion object {
        private const val TAG = "DitingVpnService"

        private const val LOG_PREFS = "dns_vpn_prefs"

        const val ACTION_START = "com.haoze.diting.START_VPN"
        const val ACTION_STOP = "com.haoze.diting.STOP_VPN"

        const val ACTION_RELOAD_RULES = "com.haoze.diting.RELOAD_RULES"

        const val EXTRA_DNS_CONFIG = "dns_config"
        const val EXTRA_OUTBOUND_PROXY = "outbound_proxy"

        const val EXTRA_PROXY_APP = "proxy_app_package"
        const val EXTRA_BYPASS_LAN = "bypass_lan"
        const val EXTRA_IPV6_MODE = "ipv6_mode"
        const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"

        const val EXTRA_BLOCKED_PACKAGES = "blocked_packages"

        const val EXTRA_INSPECTION_PACKAGES = "inspection_packages"

        const val EXTRA_INSPECTION_ENABLED = "inspection_enabled"

        private const val CHANNEL_ID = "diting_vpn"
        private const val NOTIFICATION_ID = 1001

        internal const val PREFS_NAME = NormalVpnRuntime.PREFS_NAME
        private const val KEY_LOG_MODE = "dns_log_mode"

        internal const val KEY_LAST_DNS_CONFIG = "last_dns_config"

        private const val KEY_HTTPS_BYPASS_RULES = "https_bypass_rules"

        var isRunning: Boolean
            get() = NormalVpnRuntime.isRunning
            set(value) {
                NormalVpnRuntime.isRunning = value
            }

        var startedAt: Long
            get() = NormalVpnRuntime.startedAt
            set(value) {
                NormalVpnRuntime.startedAt = value
            }

        private var activeEngine: Engine?
            get() = NormalVpnRuntime.engine
            set(value) {
                NormalVpnRuntime.engine = value
            }

        internal fun engineForDiagnostics(): Engine? = activeEngine

        var lastError: String?
            get() = NormalVpnRuntime.lastError
            set(value) {
                NormalVpnRuntime.lastError = value
            }

        var reclaiming: Boolean
            get() = NormalVpnRuntime.reclaiming
            set(value) {
                NormalVpnRuntime.reclaiming = value
            }

        fun isPersistedRunning(context: Context): Boolean =
            NormalVpnRuntime.isPersistedRunning(context)

        fun setPersistedRunning(context: Context, value: Boolean) =
            NormalVpnRuntime.setPersistedRunning(context, value)

        fun refreshNotification(context: Context): Boolean =
            isRunning && VpnNotification.rerender(context, CHANNEL_ID, NOTIFICATION_ID, ACTION_STOP)

        fun status(context: Context): Map<String, Any?> = NormalVpnRuntime.status(context)

        fun trafficRates(): Map<String, Any?> = NormalVpnRuntime.trafficRates()

        fun startIntent(
            context: Context,
            dnsConfig: String,
            proxyJson: String,
            bypassLan: Boolean,
            ipv6Mode: String,
            excludedPackages: List<String>,
            proxyAppPackage: String = "",
            blockedPackages: List<String> = emptyList(),
            inspectionPackages: List<String> = emptyList(),
            inspectionEnabled: Boolean = false,
        ): Intent = Intent(context, DitingVpnService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_DNS_CONFIG, dnsConfig)
            putExtra(EXTRA_OUTBOUND_PROXY, proxyJson)
            putExtra(EXTRA_PROXY_APP, proxyAppPackage)
            putExtra(EXTRA_BYPASS_LAN, bypassLan)
            putExtra(EXTRA_IPV6_MODE, ipv6Mode)
            putStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES, ArrayList(excludedPackages))
            putStringArrayListExtra(EXTRA_BLOCKED_PACKAGES, ArrayList(blockedPackages))
            putStringArrayListExtra(EXTRA_INSPECTION_PACKAGES, ArrayList(inspectionPackages))
            putExtra(EXTRA_INSPECTION_ENABLED, inspectionEnabled)
        }

        fun stopIntent(context: Context): Intent =
            Intent(context, DitingVpnService::class.java).setAction(ACTION_STOP)

        fun requestReload(context: Context) {
            if (!isRunning) return
            runCatching { context.startService(reloadIntent(context)) }
        }

        fun reloadIntent(context: Context): Intent =
            Intent(context, DitingVpnService::class.java).setAction(ACTION_RELOAD_RULES)

        fun restoreIntent(context: Context): Intent? = VpnStartConfig.restoreIntent(context)
    }
}
