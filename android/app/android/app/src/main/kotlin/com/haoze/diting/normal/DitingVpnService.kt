package com.haoze.diting.normal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.R
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineLogCallbacks
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.PackageUids
import com.haoze.diting.log.RequestStats
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.overlay.FloatingLogOverlay
import com.haoze.diting.proxy.OutboundProxyBridge
import com.haoze.diting.proxy.OutboundProxyScope
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.watchdog.VpnReclaimer
import tunnel.Engine
import tunnel.OutboundProxyStatusCallback
import tunnel.SocketProtector
import java.io.File

/// Full-tunnel VpnService: applies the config, then hands the TUN fd to Engine.startFull.
class DitingVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var engine: Engine? = null
    private var dataPlane: EngineDataPlane? = null

    @Volatile
    private var worker: Thread? = null

    @Volatile
    private var stopping = false

    private val speedTicker = SpeedTicker(
        context = this,
        active = { isRunning && !stopping },
        onTick = { VpnNotification.refresh(this, CHANNEL_ID, NOTIFICATION_ID, ACTION_STOP) },
    )

    /// Follows a revoke caused by another VPN and reconnects once that VPN lets go of the slot.
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
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        if (intent?.action == ACTION_STOP) {
            stopTunnel()
            return START_NOT_STICKY
        }
        // A start, manual or replayed by the watchdog, ends any wait for the slot.
        reclaimer.cancel()
        val dnsConfig = intent?.getStringExtra(EXTRA_DNS_CONFIG)
        if (dnsConfig.isNullOrBlank()) {
            Log.w(TAG, "start intent without DNS config")
            stopTunnel()
            return START_NOT_STICKY
        }
        // Persisted so the quick settings tile (and a future reboot restore) can rebuild the same
        // start intent: Dart computes the config, the extras do not survive elsewhere.
        VpnStartConfig.remember(
            context = this,
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty(),
            bypassLan = intent.getBooleanExtra(EXTRA_BYPASS_LAN, true),
            ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: "auto",
            excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet(),
            blockedPackages = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES).orEmpty().toSet(),
            inspectionPackages = intent.getStringArrayListExtra(EXTRA_INSPECTION_PACKAGES).orEmpty().toSet(),
            inspectionEnabled = intent.getBooleanExtra(EXTRA_INSPECTION_ENABLED, false),
        )
        startTunnel(
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty(),
            bypassLan = intent.getBooleanExtra(EXTRA_BYPASS_LAN, true),
            ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: "auto",
            excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet(),
            blockedPackages = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES).orEmpty().toSet(),
            inspectionPackages = intent.getStringArrayListExtra(EXTRA_INSPECTION_PACKAGES).orEmpty().toSet(),
            inspectionEnabled = intent.getBooleanExtra(EXTRA_INSPECTION_ENABLED, false),
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
        stopping = false
        lastError = null

        val pfd = VpnRouteConfig.establish(
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

        val goEngine = try {
            Engine()
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to load Go engine", t)
            releaseResources()
            fail("Go 引擎加载失败：${t.message ?: t.javaClass.simpleName}")
            return
        }
        engine = goEngine
        activeEngine = goEngine

        try {
            val proxyError = goEngine.configureOutboundProxy(
                OutboundProxyScope.resolve(this, proxyJson.ifBlank { VpnStartConfig.DEFAULT_OUTBOUND_PROXY })
            )
            if (proxyError.isNotBlank()) {
                // Persisted before failing so the page shows the reason, as the legacy app did.
                OutboundProxyBridge.publishStatus(this@DitingVpnService, "error", proxyError)
            }
            require(proxyError.isBlank()) { proxyError }
            // Registered before startFull, which already emits `connecting`; without this the
            // engine's ready/error result never reaches `dns_vpn_prefs` and the page stays on
            // "正在连接" forever.
            goEngine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
                override fun onOutboundProxyStatus(state: String, message: String) {
                    OutboundProxyBridge.publishStatus(this@DitingVpnService, state, message)
                }
            })
            goEngine.applyDNSConfig(dnsConfig)
            val logMode = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
                ?: DnsLogWriter.MODE_ALL
            // Counts belong to this run; the notification shows them since the tunnel came up.
            RequestStats.reset()
            EngineLogCallbacks.attach(goEngine, this, DnsLogWriter.DB_NORMAL, logMode)
            goEngine.setFilterDNS(true)
            goEngine.setUseTcpStack(true)

            // Attached before startFull and assigned first, so a throw still reaches cleanup.
            val plane = EngineDataPlane(this, logMode)
            dataPlane = plane
            plane.attachResolvers(goEngine)
            plane.attachBootstrap(goEngine)
            plane.attachCacheMirror(goEngine)
            plane.attachTraffic(goEngine)
            plane.attachHttp(goEngine)

            // Per-app firewall: the engine matches UIDs, not package names.
            val blockedUidCsv = PackageUids.csv(this, blockedPackages)
            if (blockedUidCsv.isNotEmpty()) {
                goEngine.setBlockedUIDs(blockedUidCsv)
            }

            // Order matters: reversed, the UID list from setMitmAllowedUIDs is silently dropped.
            if (inspectionEnabled) {
                val mitmDir = File(filesDir, MITM_DIR).apply { mkdirs() }
                val caPem = runCatching { goEngine.startStackMitm(mitmDir.absolutePath) }
                    .getOrDefault("")
                if (caPem.isBlank()) {
                    // No CA means no filter, so startFull builds a plain passthrough stack.
                    Log.w(TAG, "startStackMitm produced no CA; HTTPS inspection stays off")
                } else {
                    goEngine.setMitmAllowedUIDs(PackageUids.csv(this, inspectionPackages))
                }
            } else {
                // Inspect nobody: the Go setter logs "stack MITM is not active" - expected.
                goEngine.setMitmAllowedUIDs("")
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to configure Go engine", t)
            releaseResources()
            fail("隧道配置失败：${t.message ?: t.javaClass.simpleName}")
            return
        }

        isRunning = true
        // Authoritative start time: the UI is a separate process and loses its own clock when
        // Android recreates it, which used to restart the uptime counter at zero.
        startedAt = System.currentTimeMillis()
        setPersistedRunning(this, true)
        startSpeedTicker()
        FloatingLogOverlay.setVpnRunning(this, true)
        // The window only matters while logs are written, and this service outlives the UI.
        LogRetention.start(
            context = this,
            databaseName = LOG_DATABASE,
            prefsName = LOG_PREFS,
            includeHttpAndTraffic = true,
        )
        worker = Thread({
            try {
                // Rules are built here, off the main thread: a stale index means a trie compile
                // that can take seconds, and onStartCommand would otherwise ANR the service.
                // Applied before startFull so the tunnel comes up with filtering already armed.
                try {
                    EngineRuleLoader.apply(this, goEngine, RuleDataset.NORMAL, TAG)
                } catch (t: Throwable) {
                    Log.e(TAG, "Unable to build rule snapshot", t)
                    if (!stopping) {
                        fail("规则加载失败：${t.message ?: t.javaClass.simpleName}")
                        return@Thread
                    }
                }
                goEngine.startFull(pfd.fd.toLong(), SocketProtector { fd ->
                    protect(fd.toInt())
                })
                Log.i(TAG, "Go tunnel exited")
            } catch (t: Throwable) {
                Log.e(TAG, "Go tunnel crashed", t)
                if (!stopping) {
                    fail("隧道运行异常：${t.message ?: t.javaClass.simpleName}")
                }
            }
        }, "diting-tunnel").also { it.start() }
    }

    @Synchronized
    private fun stopTunnel() {
        reclaimer.cancel()
        teardown()
        setPersistedRunning(this, false)
        stopForegroundCompat()
        stopSelf()
    }

    /// Stops the engine and frees the TUN; the service, its foreground state and the persisted
    /// running flag are left to the caller.
    @Synchronized
    private fun teardown() {
        stopping = true
        val current = engine
        engine = null
        activeEngine = null
        runCatching { current?.stop() }
            .onFailure { Log.w(TAG, "engine.stop failed", it) }
        runCatching { current?.stopStackMitm() }
        runCatching { current?.releaseTun() }
        closeDataPlane()
        releaseResources()
        isRunning = false
        startedAt = 0L
        FloatingLogOverlay.setVpnRunning(this, false)
    }

    /// Flushes buffered traffic / HTTP rows; runs after the engine stopped, so nothing appends
    private fun closeDataPlane() {
        val plane = dataPlane
        dataPlane = null
        runCatching { plane?.close() }
    }

    private fun releaseResources() {
        runCatching { tun?.close() }
        tun = null
        worker = null
        // Stopped too: the failure path returns before `isRunning` is set, leaking a ticker.
        stopSpeedTicker()
        // Covers the failure paths, which never reach teardown().
        FloatingLogOverlay.setVpnRunning(this, false)
        TrafficRateMonitor.reset()
        // The sweep belongs to the tunnel's lifetime; otherwise it outlives the service.
        LogRetention.stop()
    }

    private fun fail(message: String) {
        lastError = message
        isRunning = false
        startedAt = 0L
        activeEngine = null
        closeDataPlane()
        setPersistedRunning(this, false)
        releaseResources()
        stopForegroundCompat()
        stopSelf()
    }

    override fun onRevoke() {
        if (reclaimer.shouldFollow()) {
            // The service stays started and in the foreground so it is alive when the slot
            // frees up; the persisted flag keeps saying "the user wants this running".
            Log.w(TAG, "VPN revoked; waiting for the slot to free up")
            teardown()
            QuickSettingsTileUpdater.requestTileUpdate(this)
            reclaimer.begin()
            // super.onRevoke() would stopSelf().
            return
        }
        Log.w(TAG, "VPN permission revoked")
        stopTunnel()
        super.onRevoke()
    }

    override fun onDestroy() {
        reclaimer.cancel()
        if (engine != null || isRunning || dataPlane != null) {
            teardown()
            setPersistedRunning(this, false)
            stopForegroundCompat()
        }
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            // Android 12+ requires foreground promotion inside onStartCommand; failing is a crash.
            Log.e(TAG, "startForeground failed", t)
        }
    }

    private fun buildNotification(): Notification =
        VpnNotification.build(this, CHANNEL_ID, NOTIFICATION_ID, ACTION_STOP)

    private fun startSpeedTicker() = speedTicker.start()

    private fun stopSpeedTicker() = speedTicker.stop()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "VPN 服务",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持 VPN 隧道运行"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    companion object {
        private const val TAG = "DitingVpnService"

        private const val LOG_DATABASE = "diting_database"

        /// `RuleDataset.NORMAL.prefsName()`: `log_retention_days` is dataset-scoped
        private const val LOG_PREFS = "dns_vpn_prefs"

        const val ACTION_START = "com.haoze.diting.START_VPN"
        const val ACTION_STOP = "com.haoze.diting.STOP_VPN"

        const val EXTRA_DNS_CONFIG = "dns_config"
        const val EXTRA_OUTBOUND_PROXY = "outbound_proxy"

        /// Package of the app that owns the loopback proxy port; excluded from the TUN.
        const val EXTRA_PROXY_APP = "proxy_app_package"
        const val EXTRA_BYPASS_LAN = "bypass_lan"
        const val EXTRA_IPV6_MODE = "ipv6_mode"
        const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"

        /// `blocked_app_packages`: converted to UIDs for `setBlockedUIDs`
        const val EXTRA_BLOCKED_PACKAGES = "blocked_packages"

        /// `http_inspection_app_packages`: converted to UIDs for `setMitmAllowedUIDs`
        const val EXTRA_INSPECTION_PACKAGES = "inspection_packages"

        /// Precomputed by Dart: without the CA every HTTPS request in those apps breaks
        const val EXTRA_INSPECTION_ENABLED = "inspection_enabled"

        private const val CHANNEL_ID = "diting_vpn"
        private const val NOTIFICATION_ID = 1001

        internal const val PREFS_NAME = "dns_vpn_prefs"
        private const val KEY_VPN_RUNNING = "vpn_running"
        private const val KEY_LOG_MODE = "dns_log_mode"

        // Last start configuration, replayed by the quick settings tile.
        internal const val KEY_LAST_DNS_CONFIG = "last_dns_config"

        /// Same directory the legacy app used: an upgraded install keeps its trusted root CA
        private const val MITM_DIR = "go-mitm"

        @Volatile
        var isRunning: Boolean = false

        /// Epoch millis of the last successful start; 0 while stopped. The UI process can be
        /// recreated at any time, so the only trustworthy origin for the uptime figure is here.
        @Volatile
        var startedAt: Long = 0L

        @Volatile
        private var activeEngine: Engine? = null

        /// Read-only handle for the diagnostics channel
        internal fun engineForDiagnostics(): Engine? = activeEngine

        @Volatile
        var lastError: String? = null

        /// Displaced by another VPN and waiting to reconnect; [isRunning] is false meanwhile.
        @Volatile
        var reclaiming: Boolean = false

        fun isPersistedRunning(context: Context): Boolean =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_VPN_RUNNING, false)

        private fun Context.setRunningFlag(value: Boolean) {
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_VPN_RUNNING, value)
                .apply()
        }

        fun setPersistedRunning(context: Context, value: Boolean) {
            context.setRunningFlag(value)
            // The tile lives in another UI surface; it only repaints when told to re-read.
            QuickSettingsTileUpdater.requestTileUpdate(context)
        }

        /// Rebuilds the posted notification after a settings change; false when nothing is posted
        fun refreshNotification(context: Context): Boolean =
            isRunning && VpnNotification.rerender(context, CHANNEL_ID, NOTIFICATION_ID, ACTION_STOP)

        fun status(context: Context): Map<String, Any?> = mapOf(
            "running" to isRunning,
            "reclaiming" to reclaiming,
            "persisted" to isPersistedRunning(context),
            "error" to lastError,
            // Milliseconds since the tunnel came up; Dart uses it instead of its own clock.
            "startedAt" to startedAt,
            "stats" to EngineStats.snapshot(activeEngine),
        )

        /// Second-resolution TX/RX rates; zeros while stopped, or the last tick if racing the stop
        fun trafficRates(): Map<String, Any?> {
            if (!isRunning) {
                return mapOf("running" to false, "txBps" to 0L, "rxBps" to 0L)
            }
            val (tx, rx) = TrafficRateMonitor.snapshot()
            return mapOf("running" to true, "txBps" to tx, "rxBps" to rx)
        }

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

        /// Rebuilds the last start intent so the tile can restart the tunnel without Dart, which
        /// is where the DNS config is computed. Null until the service was started at least once.
        fun restoreIntent(context: Context): Intent? = VpnStartConfig.restoreIntent(context)
    }
}
