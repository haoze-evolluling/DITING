package com.haoze.diting.normal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.R
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.OutboundProxyStatusCallback
import com.haoze.diting.engine.SocketProtector
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineLogCallbacks
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.PackageUids
import com.haoze.diting.log.RequestStats
import com.haoze.diting.log.TrafficRateMonitor
import com.haoze.diting.overlay.FloatingLogOverlay
import com.haoze.diting.proxy.OutboundProxyBridge
import com.haoze.diting.proxy.OutboundProxyScope
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.watchdog.VpnReclaimer
import java.io.File

/// Full-tunnel VpnService on the Rust engine: applies the config, then hands the TUN fd to
/// `Engine.startFull`. HTTPS inspection (MITM) runs inside the same engine since stage 4b.
class DitingVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var engine: Engine? = null
    private var dataPlane: EngineDataPlane? = null

    @Volatile
    private var worker: Thread? = null

    @Volatile
    private var stopping = false

    private val mainHandler = Handler(Looper.getMainLooper())

    /// Bumped by every accepted start. A stop hands its shutdown to a worker, and by the time it
    /// comes back a new start may own the ticker, retention and foreground state; the generation
    /// tells it so instead of tearing the new run down.
    private var tunnelGeneration = 0

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
        if (intent?.action == ACTION_RELOAD_RULES) {
            reloadRules()
            return START_NOT_STICKY
        }
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
        val defaults = VpnPlanNative.startDefaults
        // Persisted so the quick settings tile (and a future reboot restore) can rebuild the same
        // start intent: Dart computes the config, the extras do not survive elsewhere.
        VpnStartConfig.remember(
            context = this,
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty(),
            bypassLan = intent.getBooleanExtra(EXTRA_BYPASS_LAN, defaults.bypassLan),
            ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: defaults.ipv6Mode,
            excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet(),
            blockedPackages = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES).orEmpty().toSet(),
            inspectionPackages = intent.getStringArrayListExtra(EXTRA_INSPECTION_PACKAGES).orEmpty().toSet(),
            inspectionEnabled = intent.getBooleanExtra(EXTRA_INSPECTION_ENABLED, defaults.inspectionEnabled),
        )
        startTunnel(
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty(),
            bypassLan = intent.getBooleanExtra(EXTRA_BYPASS_LAN, defaults.bypassLan),
            ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: defaults.ipv6Mode,
            excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet(),
            blockedPackages = intent.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES).orEmpty().toSet(),
            inspectionPackages = intent.getStringArrayListExtra(EXTRA_INSPECTION_PACKAGES).orEmpty().toSet(),
            inspectionEnabled = intent.getBooleanExtra(EXTRA_INSPECTION_ENABLED, defaults.inspectionEnabled),
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
            releaseResources()
            fail("引擎加载失败：${t.message ?: t.javaClass.simpleName}")
            return
        }
        engine = rustEngine
        activeEngine = rustEngine

        try {
            val proxyError = rustEngine.configureOutboundProxy(
                OutboundProxyScope.resolve(this, proxyJson.ifBlank { VpnPlanNative.startDefaults.outboundProxy })
            )
            if (proxyError.isNotBlank()) {
                // Persisted before failing so the page shows the reason, as the legacy app did.
                OutboundProxyBridge.publishStatus(this@DitingVpnService, "error", proxyError)
            }
            require(proxyError.isBlank()) { proxyError }
            // Registered before startFull, which already emits `connecting`; without this the
            // engine's ready/error result never reaches `dns_vpn_prefs` and the page stays on
            // "正在连接" forever.
            rustEngine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
                override fun onOutboundProxyStatus(state: String, message: String) {
                    OutboundProxyBridge.publishStatus(this@DitingVpnService, state, message)
                }
            })
            // Throws with the engine's rejection text.
            rustEngine.applyDNSConfig(dnsConfig)
            val logMode = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
                ?: DnsLogWriter.MODE_ALL
            // Counts belong to this run; the notification shows them since the tunnel came up.
            RequestStats.reset()
            EngineLogCallbacks.attach(rustEngine, this, DnsLogWriter.DB_NORMAL, logMode)
            rustEngine.setFilterDNS(true)
            // The tunnel resolved `ipv6Mode` against the link (AUTO probe included). When it is
            // carrying no IPv6, answer AAAA with NODATA so traffic does not stall on IPv6.
            rustEngine.setBlockIpv6(!ipv6Enabled)

            // Attached before startFull and assigned first, so a throw still reaches cleanup.
            val plane = EngineDataPlane(this, logMode)
            dataPlane = plane
            plane.attachResolvers(rustEngine)
            plane.attachBootstrap(rustEngine)
            plane.attachCacheMirror(rustEngine)
            plane.attachTraffic(rustEngine)
            plane.attachHttp(rustEngine)

            // Per-app firewall: the engine matches UIDs, not package names.
            val blockedUidCsv = PackageUids.csv(this, blockedPackages)
            if (blockedUidCsv.isNotEmpty()) {
                rustEngine.setBlockedUIDs(blockedUidCsv)
            }

            // Order matters: reversed, the UID list from setMitmAllowedUIDs is silently dropped.
            if (inspectionEnabled) {
                val mitmDir = File(filesDir, MITM_DIR).apply { mkdirs() }
                val caPem = runCatching { rustEngine.startStackMitm(mitmDir.absolutePath) }
                    .getOrDefault("")
                if (caPem.isBlank()) {
                    // No CA means no filter, so startFull builds a plain passthrough stack.
                    Log.w(TAG, "startStackMitm produced no CA; HTTPS inspection stays off")
                } else {
                    rustEngine.setMitmAllowedUIDs(PackageUids.csv(this, inspectionPackages))
                    // The custom half of the bypass list is persisted by the inspection page as
                    // one suffix per row. The old Go engine never received it (its setter had no
                    // caller), so this is where the list finally reaches the filter.
                    val bypass = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                        .getStringSet(KEY_HTTPS_BYPASS_RULES, null)
                        .orEmpty()
                    if (bypass.isNotEmpty()) {
                        rustEngine.setHttpsBypassRules(bypass.joinToString("\n"))
                    }
                    // Drop QUIC for the inspected apps only, so HTTP/3 falls back to TCP and the
                    // flows the user selected actually reach the MITM path.
                    rustEngine.setFilterHttp3(true)
                }
            } else {
                // Inspect nobody: the setter logs "stack MITM is not active" - expected.
                rustEngine.setMitmAllowedUIDs("")
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to configure the engine", t)
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
                    EngineRuleLoader.apply(this, rustEngine, RuleDataset.NORMAL, TAG)
                } catch (t: Throwable) {
                    Log.e(TAG, "Unable to build rule snapshot", t)
                    if (!stopping) {
                        fail("规则加载失败：${t.message ?: t.javaClass.simpleName}")
                        return@Thread
                    }
                }
                rustEngine.startFull(pfd.fd.toLong(), object : SocketProtector {
                    override fun protect(fd: Long): Boolean = protect(fd.toInt())
                })
                // `startFull` returns once the session is up (the old Go method blocked until `stop`).
                // Polling keeps this thread the one place a self-terminated session is reported.
                while (!stopping && rustEngine.isFullRunning()) {
                    Thread.sleep(SESSION_POLL_MS)
                }
                Log.i(TAG, "tunnel exited")
            } catch (t: Throwable) {
                Log.e(TAG, "tunnel crashed", t)
                if (!stopping) {
                    fail("隧道运行异常：${t.message ?: t.javaClass.simpleName}")
                }
            }
        }, "diting-tunnel").also { it.start() }
    }

    /// Rebuilds the rule snapshot and re-applies it to the running engine so a newly imported or
    /// updated subscription takes effect without dropping the tunnel. A failure keeps the previous
    /// rules (the policy swap only happens once the new snapshot builds) instead of killing the VPN.
    private fun reloadRules() {
        val current = engine
        if (current == null || !isRunning) {
            Log.i(TAG, "rule reload requested but the tunnel is not running")
            return
        }
        Thread({
            try {
                EngineRuleLoader.apply(this, current, RuleDataset.NORMAL, TAG)
                Log.i(TAG, "rule snapshot hot-reloaded")
            } catch (t: Throwable) {
                Log.e(TAG, "rule hot-reload failed; keeping previous rules", t)
            }
        }, "diting-rule-reload").start()
    }

    /// Stops the tunnel without blocking the caller's thread for the shutdown.
    ///
    /// `engine.stop()` alone takes 200 ms and more (plus the queued-row flush), and a service
    /// runs on the app's main thread - which is also Flutter's UI thread. Doing it inline froze
    /// the whole UI for that long, and an animation started by the same tap (the power button's
    /// collapse) skipped straight to its end when the thread resumed. So the resources are
    /// detached here, on the caller's thread, and shut down on a throwaway worker.
    @Synchronized
    private fun stopTunnel() {
        reclaimer.cancel()
        // Detached before handing off: nothing can append to the plane while it flushes, the
        // poll loop on the tunnel thread sees `stopping` at once, and a start that races this
        // stop cannot pick up half-dead resources. Re-entering here is harmless: a second call
        // finds nulls and only repeats the service bookkeeping.
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
                // A start that landed meanwhile owns the ticker, retention and foreground state.
                if (generation != tunnelGeneration) return@post
                releaseResources()
                setPersistedRunning(this@DitingVpnService, false)
                stopForegroundCompat()
                stopSelf()
            }
        }, "diting-teardown").start()
    }

    /// Stops the engine and frees the TUN; the service, its foreground state and the persisted
    /// running flag are left to the caller.
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

    /// The blocking half of a shutdown: engine threads, the TUN hand-off and the row flush that
    /// `EngineDataPlane.close` performs. Already runs off the main thread on the `fail()` path.
    private fun releaseTunnel(engine: Engine?, plane: EngineDataPlane?) {
        runCatching { engine?.stop() }
            .onFailure { Log.w(TAG, "engine.stop failed", it) }
        runCatching { engine?.stopStackMitm() }
        runCatching { engine?.releaseTun() }
        runCatching { plane?.close() }
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

        /// Re-applies the rule snapshot to the already-running tunnel (no drop/reconnect).
        const val ACTION_RELOAD_RULES = "com.haoze.diting.RELOAD_RULES"

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

        /// `https_bypass_rules` in `dns_vpn_prefs`: the custom MITM bypass list, one suffix per row
        private const val KEY_HTTPS_BYPASS_RULES = "https_bypass_rules"

        /// How often the tunnel thread checks whether the session it started is still running.
        private const val SESSION_POLL_MS = 200L

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

        /// Asks a running tunnel to rebuild its rules in place. A no-op when it is not running:
        /// starting the service just to reload would post a foreground notification with no tunnel.
        fun requestReload(context: Context) {
            if (!isRunning) return
            runCatching { context.startService(reloadIntent(context)) }
        }

        fun reloadIntent(context: Context): Intent =
            Intent(context, DitingVpnService::class.java).setAction(ACTION_RELOAD_RULES)

        /// Rebuilds the last start intent so the tile can restart the tunnel without Dart, which
        /// is where the DNS config is computed. Null until the service was started at least once.
        fun restoreIntent(context: Context): Intent? = VpnStartConfig.restoreIntent(context)
    }
}
