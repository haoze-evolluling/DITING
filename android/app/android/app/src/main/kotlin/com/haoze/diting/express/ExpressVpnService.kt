package com.haoze.diting.express

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.StorageGate
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.SocketProtector
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.log.LogRetention
import com.haoze.diting.normal.SpeedTicker
import com.haoze.diting.platform.NotificationSettings
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.UnderlyingNetworkMonitor
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.vpn.VpnServiceForeground
import com.haoze.diting.vpn.applyTo
import com.haoze.diting.watchdog.VpnReclaimer

class ExpressVpnService : VpnService() {
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
    private var tunnelIpv6Enabled = false
    private var tunnelClatOnly = false
    private var pendingRebuild = false
    private var lastRebuildAtMs = 0L

    private val statsTicker = SpeedTicker(
        context = this,
        active = { isRunning && !stopping },
        onTick = {
            if (NotificationSettings.hasLiveItems(this)) refreshNotification(this)
        },
    )

    private val reclaimer = VpnReclaimer(
        service = this,
        workMode = "express",
        modeTitle = "极速模式",
        channelId = CHANNEL_ID,
        notificationId = NOTIFICATION_ID,
        stopIntent = { stopIntent(this) },
        restoreIntent = { restoreIntent(this) },
        onWaitingChanged = { reclaiming = it },
        onGiveUp = { stopTunnel() },
    )

    override fun onCreate() {
        super.onCreate()
        RuntimeEventLog.info("express", "service.create")
        VpnServiceForeground.createChannel(this, CHANNEL_ID, "极速模式", "保持 DNS 窄路由 VPN 运行")
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
            RuntimeEventLog.warn("express", "start.no_config")
            stopTunnel()
            return START_NOT_STICKY
        }
        val defaults = VpnPlanNative.startDefaults
        val proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty()
        val proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty()
        val ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: defaults.ipv6Mode
        val excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet()
        ExpressStartConfig.remember(
            context = this,
            dnsConfig = dnsConfig,
            proxyJson = proxyJson,
            proxyAppPackage = proxyAppPackage,
            ipv6Mode = ipv6Mode,
            excludedPackages = excludedPackages,
        )
        startTunnel(
            dnsConfig = dnsConfig,
            proxyJson = proxyJson,
            proxyAppPackage = proxyAppPackage,
            ipv6Mode = ipv6Mode,
            excludedPackages = excludedPackages,
        )
        return START_NOT_STICKY
    }

    @Synchronized
    private fun startTunnel(
        dnsConfig: String,
        proxyJson: String,
        proxyAppPackage: String,
        ipv6Mode: String,
        excludedPackages: Set<String>,
    ) {
        if (engine != null) {
            Log.i(TAG, "express tunnel already running; ignoring duplicate start")
            return
        }
        tunnelGeneration++
        stopping = false
        lastError = null

        val established = ExpressRouteConfig.establish(
            service = this,
            excludedPackages = excludedPackages,
            proxyPackage = proxyAppPackage.ifBlank { null },
            ipv6Mode = ipv6Mode,
        )
        val pfd = established.fd
        val ipv6Enabled = established.ipv6Enabled
        if (pfd == null) {
            fail("无法建立极速模式接口")
            return
        }
        tun = pfd
        tunnelIpv6Enabled = ipv6Enabled
        tunnelClatOnly = established.clatOnly

        val rustEngine = try {
            Engine()
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to load the engine", t)
            RuntimeEventLog.error("express", "engine.load_fail", "error" to (t.message ?: t.javaClass.simpleName))
            releaseResources()
            fail("引擎加载失败：${t.message ?: t.javaClass.simpleName}")
            return
        }
        engine = rustEngine
        activeEngine = rustEngine

        try {
            val logMode = getSharedPreferences(SETTINGS_PREFS, MODE_PRIVATE)
                .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
                ?: DnsLogWriter.MODE_ALL
            dataPlane = ExpressEngineConfig.configure(
                service = this,
                engine = rustEngine,
                dnsConfig = dnsConfig,
                proxyJson = proxyJson,
                ipv6Enabled = ipv6Enabled,
                logMode = logMode,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to configure the engine", t)
            RuntimeEventLog.error("express", "engine.config_fail", "error" to (t.message ?: t.javaClass.simpleName))
            releaseResources()
            fail("极速模式配置失败：${t.message ?: t.javaClass.simpleName}")
            return
        }

        networkMonitor = UnderlyingNetworkMonitor(this, this) { state ->
            state.applyTo(rustEngine, ipv6Mode)
            if (topologyChanged(state, ipv6Mode)) requestTunnelRebuild()
        }.also { it.start() }

        isRunning = true
        startedAt = System.currentTimeMillis()
        setPersistedRunning(this, true)
        statsTicker.start()
        LogRetention.start(
            context = this,
            databaseName = RuleDataset.EXPRESS.logsDatabase(),
            prefsName = LOG_PREFS,
            includeHttpAndTraffic = false,
        )
        worker = Thread({
            try {
                try {
                    EngineRuleLoader.apply(this, rustEngine, RuleDataset.EXPRESS, TAG)
                } catch (t: Throwable) {
                    Log.e(TAG, "Unable to build rule snapshot", t)
                    RuntimeEventLog.error(
                        "express",
                        "rule.snapshot_fail",
                        "error" to (t.message ?: t.javaClass.simpleName),
                    )
                    if (!stopping) {
                        fail("规则加载失败：${t.message ?: t.javaClass.simpleName}")
                        return@Thread
                    }
                }
                rustEngine.startFull(pfd.fd.toLong(), object : SocketProtector {
                    override fun protect(fd: Long): Boolean = protect(fd.toInt())
                })
                while (!stopping && rustEngine.isFullRunning()) {
                    Thread.sleep(SESSION_POLL_MS)
                }
                Log.i(TAG, "express tunnel exited")
            } catch (t: Throwable) {
                Log.e(TAG, "express tunnel crashed", t)
                RuntimeEventLog.error(
                    "express",
                    "tunnel.crashed",
                    "error" to (t.message ?: t.javaClass.simpleName),
                )
                if (!stopping) {
                    fail("极速模式运行异常：${t.message ?: t.javaClass.simpleName}")
                }
            }
        }, "diting-express-tunnel").also { it.start() }
    }

    private fun reloadRules() {
        val current = engine
        if (current == null || !isRunning) {
            Log.i(TAG, "rule reload requested but the tunnel is not running")
            return
        }
        Thread({
            try {
                EngineRuleLoader.apply(this, current, RuleDataset.EXPRESS, TAG)
                Log.i(TAG, "rule snapshot hot-reloaded")
            } catch (t: Throwable) {
                Log.e(TAG, "rule hot-reload failed; keeping previous rules", t)
                RuntimeEventLog.warn(
                    "express",
                    "rule.reload_fail",
                    "error" to (t.message ?: t.javaClass.simpleName),
                )
            }
        }, "diting-rule-reload").start()
    }

    private fun topologyChanged(
        state: UnderlyingNetworkMonitor.State,
        ipv6Mode: String,
    ): Boolean {
        val ipv6Changed =
            VpnPlanNative.ipv6ProbeNeeded(ipv6Mode) && state.physicalIpv6 != tunnelIpv6Enabled
        return ipv6Changed || state.clat != tunnelClatOnly
    }

    private fun requestTunnelRebuild() {
        if (stopping || pendingRebuild || engine == null) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastRebuildAtMs < REBUILD_COOLDOWN_MS) return
        lastRebuildAtMs = now
        pendingRebuild = true
        RuntimeEventLog.warn("express", "tunnel.rebuild", "reason" to "network-topology")
        stopTunnel(rebuild = true)
    }

    @Synchronized
    private fun stopTunnel(rebuild: Boolean = false) {
        reclaimer.cancel()
        if (!rebuild) pendingRebuild = false
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
        Thread({
            releaseTunnel(current, plane)
            runCatching { currentTun?.close() }
            mainHandler.post {
                if (generation != tunnelGeneration) return@post
                releaseResources()
                setPersistedRunning(this@ExpressVpnService, false)
                if (pendingRebuild) {
                    pendingRebuild = false
                    val intent = ExpressStartConfig.restoreIntent(this@ExpressVpnService)
                    if (intent != null && runCatching { startService(intent) }.isSuccess) {
                        return@post
                    }
                    Log.w(TAG, "tunnel rebuild could not restart the service")
                }
                VpnServiceForeground.stop(this@ExpressVpnService)
                stopSelf()
            }
        }, "diting-express-teardown").start()
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
    }

    private fun releaseTunnel(engine: Engine?, plane: EngineDataPlane?) {
        runCatching { engine?.stop() }
            .onFailure { Log.w(TAG, "engine.stop failed", it) }
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
        statsTicker.stop()
        LogRetention.stop()
    }

    private fun fail(message: String) {
        RuntimeEventLog.error("express", "tunnel.fail", "message" to message)
        pendingRebuild = false
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
        RuntimeEventLog.warn("express", "revoked")
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
        RuntimeEventLog.info("express", "service.destroy")
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
            ExpressNotification.build(this, CHANNEL_ID, ACTION_STOP),
        ) ?: return
        Log.e(TAG, "startForeground failed", error)
        RuntimeEventLog.error("express", "foreground.fail", "error" to (error.message ?: error.javaClass.simpleName))
    }

    companion object {
        private const val TAG = "ExpressVpnService"

        private const val LOG_PREFS = "diting_express_prefs"

        const val ACTION_START = "com.haoze.diting.express.START_VPN"
        const val ACTION_STOP = "com.haoze.diting.express.STOP_VPN"

        const val ACTION_RELOAD_RULES = "com.haoze.diting.express.RELOAD_RULES"

        const val EXTRA_DNS_CONFIG = "dns_config"
        const val EXTRA_OUTBOUND_PROXY = "outbound_proxy"

        const val EXTRA_PROXY_APP = "proxy_app_package"
        const val EXTRA_IPV6_MODE = "ipv6_mode"
        const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"

        private const val CHANNEL_ID = "channel_express"
        private const val NOTIFICATION_ID = 2003
        internal const val PREFS_NAME = "express_vpn_prefs"
        private const val KEY_VPN_RUNNING = "express_vpn_running"
        private const val KEY_LOG_MODE = "dns_log_mode"
        private const val SETTINGS_PREFS = "diting_express_prefs"

        internal const val KEY_LAST_DNS_CONFIG = "last_dns_config"

        private const val SESSION_POLL_MS = 200L

        /** 网络拓扑快速抖动时避免反复重建 TUN。 */
        private const val REBUILD_COOLDOWN_MS = 15_000L

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var startedAt: Long = 0L

        @Volatile
        private var activeEngine: Engine? = null

        internal fun engineForDiagnostics(): Engine? = activeEngine

        @Volatile
        var lastError: String? = null

        @Volatile
        var reclaiming: Boolean = false

        fun isPersistedRunning(context: Context): Boolean =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_VPN_RUNNING, false)

        fun setPersistedRunning(context: Context, value: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_VPN_RUNNING, value)
                .apply()
            QuickSettingsTileUpdater.requestTileUpdate(context)
        }

        fun status(context: Context): Map<String, Any?> = mapOf(
            "running" to isRunning,
            "reclaiming" to reclaiming,
            "persisted" to isPersistedRunning(context),
            "error" to lastError,
            "startedAt" to startedAt,
            "stats" to EngineStats.snapshot(activeEngine),
        )

        fun refreshNotification(context: Context): Boolean =
            isRunning && ExpressNotification.rerender(context, CHANNEL_ID, NOTIFICATION_ID, ACTION_STOP)

        fun startIntent(
            context: Context,
            dnsConfig: String,
            proxyJson: String,
            ipv6Mode: String,
            excludedPackages: List<String>,
            proxyAppPackage: String = "",
        ): Intent = Intent(context, ExpressVpnService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_DNS_CONFIG, dnsConfig)
            putExtra(EXTRA_OUTBOUND_PROXY, proxyJson)
            putExtra(EXTRA_PROXY_APP, proxyAppPackage)
            putExtra(EXTRA_IPV6_MODE, ipv6Mode)
            putStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES, ArrayList(excludedPackages))
        }

        fun stopIntent(context: Context): Intent =
            Intent(context, ExpressVpnService::class.java).setAction(ACTION_STOP)

        fun requestReload(context: Context) {
            if (!isRunning) return
            runCatching { context.startService(reloadIntent(context)) }
        }

        fun reloadIntent(context: Context): Intent =
            Intent(context, ExpressVpnService::class.java).setAction(ACTION_RELOAD_RULES)

        fun restoreIntent(context: Context): Intent? = ExpressStartConfig.restoreIntent(context)
    }
}
