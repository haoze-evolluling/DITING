package com.haoze.diting.express

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
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
import com.haoze.diting.log.RequestStats
import com.haoze.diting.normal.SpeedTicker
import com.haoze.diting.platform.NotificationMode
import com.haoze.diting.platform.NotificationSettings
import com.haoze.diting.platform.NotificationStatsLine
import com.haoze.diting.proxy.OutboundProxyBridge
import com.haoze.diting.proxy.OutboundProxyScope
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.VpnPlanNative
import com.haoze.diting.watchdog.VpnReclaimer

/// Express-mode VpnService on the Rust engine: the TUN only owns DNS routes, so the engine sees the
/// DNS queries and nothing else. Normal mode lives in `normal.DitingVpnService`.
class ExpressVpnService : VpnService() {
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

    /// Repaints the request counts; a no-op tick when no detail item is enabled.
    private val statsTicker = SpeedTicker(
        context = this,
        active = { isRunning && !stopping },
        onTick = {
            if (NotificationSettings.hasLiveItems(this)) refreshNotification(this)
        },
    )

    /// Follows a revoke caused by another VPN and reconnects once that VPN lets go of the slot.
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
        // Persisted so the quick settings tile can rebuild the same start intent: Dart computes
        // the config, the intent extras do not survive anywhere else.
        rememberStartConfig(
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty(),
            ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: defaults.ipv6Mode,
            excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet(),
        )
        startTunnel(
            dnsConfig = dnsConfig,
            proxyJson = intent.getStringExtra(EXTRA_OUTBOUND_PROXY).orEmpty(),
            proxyAppPackage = intent.getStringExtra(EXTRA_PROXY_APP).orEmpty(),
            ipv6Mode = intent.getStringExtra(EXTRA_IPV6_MODE) ?: defaults.ipv6Mode,
            excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES).orEmpty().toSet(),
        )
        return START_NOT_STICKY
    }

    /// Stores the configuration of the current start so `restoreIntent` can replay it.
    private fun rememberStartConfig(
        dnsConfig: String,
        proxyJson: String,
        proxyAppPackage: String,
        ipv6Mode: String,
        excludedPackages: Set<String>,
    ) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
            .putString(KEY_LAST_DNS_CONFIG, dnsConfig)
            .putString(KEY_LAST_OUTBOUND_PROXY, proxyJson)
            .putString(KEY_LAST_PROXY_APP, proxyAppPackage)
            .putString(KEY_LAST_IPV6_MODE, ipv6Mode)
            .putStringSet(KEY_LAST_EXCLUDED_PACKAGES, excludedPackages)
            .apply()
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

        val (pfd, ipv6Enabled) = ExpressRouteConfig.establish(
            service = this,
            excludedPackages = excludedPackages,
            proxyPackage = proxyAppPackage.ifBlank { null },
            ipv6Mode = ipv6Mode,
        )
        if (pfd == null) {
            fail("无法建立极速模式接口")
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
                OutboundProxyBridge.publishStatus(this@ExpressVpnService, "error", proxyError)
            }
            require(proxyError.isBlank()) { proxyError }
            // Emits `connecting` inside startFull; without this callback nothing ever writes the
            // final ready/error state back to `dns_vpn_prefs`.
            rustEngine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
                override fun onOutboundProxyStatus(state: String, message: String) {
                    OutboundProxyBridge.publishStatus(this@ExpressVpnService, state, message)
                }
            })
            rustEngine.applyDNSConfig(dnsConfig)
            val logMode = getSharedPreferences(SETTINGS_PREFS, MODE_PRIVATE)
                .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
                ?: DnsLogWriter.MODE_ALL
            RequestStats.reset()
            EngineLogCallbacks.attach(rustEngine, this, DnsLogWriter.DB_EXPRESS, logMode)
            rustEngine.setFilterDNS(true)
            // Same rule as the full tunnel: no IPv6 in the narrow TUN means no AAAA answers, so a
            // client whose physical IPv6 is broken does not wait on a doomed IPv6 attempt.
            rustEngine.setBlockIpv6(!ipv6Enabled)

            // Resolvers only: no user traffic crosses the narrow TUN and there is no MITM stage.
            // The log tables live in the express database, so bootstrap rows and the cache
            // mirror must target it too.
            val plane = EngineDataPlane(this, logMode, DnsLogWriter.DB_EXPRESS)
            dataPlane = plane
            plane.attachResolvers(rustEngine)
            plane.attachBootstrap(rustEngine)
            plane.attachCacheMirror(rustEngine)
        } catch (t: Throwable) {
            Log.e(TAG, "Unable to configure the engine", t)
            releaseResources()
            fail("极速模式配置失败：${t.message ?: t.javaClass.simpleName}")
            return
        }

        isRunning = true
        // Authoritative start time: a recreated UI process must not restart the uptime counter.
        startedAt = System.currentTimeMillis()
        setPersistedRunning(this, true)
        statsTicker.start()
        // Express has its own log file, so no HTTP or traffic tables.
        LogRetention.start(
            context = this,
            databaseName = LOG_DATABASE,
            prefsName = LOG_PREFS,
            includeHttpAndTraffic = false,
        )
        worker = Thread({
            try {
                // Rules are built here, off the main thread: a stale index means a trie compile
                // that can take seconds, and onStartCommand would otherwise ANR the service.
                // Applied before startFull so the tunnel comes up with filtering already armed.
                try {
                    EngineRuleLoader.apply(this, rustEngine, RuleDataset.EXPRESS, TAG)
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
                // Waiting keeps this thread as the single place a self-terminated session is
                // reported, which is what the "crashed" branch below used to cover.
                while (!stopping && rustEngine.isFullRunning()) {
                    Thread.sleep(SESSION_POLL_MS)
                }
                Log.i(TAG, "express tunnel exited")
            } catch (t: Throwable) {
                Log.e(TAG, "express tunnel crashed", t)
                if (!stopping) {
                    fail("极速模式运行异常：${t.message ?: t.javaClass.simpleName}")
                }
            }
        }, "diting-express-tunnel").also { it.start() }
    }

    /// Rebuilds the rule snapshot and re-applies it to the running engine so a newly imported or
    /// updated subscription takes effect without dropping the tunnel. A failure keeps the previous
    /// rules instead of killing the VPN.
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
            }
        }, "diting-rule-reload").start()
    }

    /// Stops the tunnel without blocking the caller's thread for the shutdown.
    ///
    /// `engine.stop()` takes hundreds of ms and a service runs on the app's main thread - which is
    /// also Flutter's UI thread. Doing it inline froze the whole UI, and an animation started by
    /// the same tap (the power button's collapse) skipped straight to its end when the thread
    /// resumed. So the resources are detached here and shut down on a throwaway worker.
    @Synchronized
    private fun stopTunnel() {
        reclaimer.cancel()
        // Detached before handing off: nothing can append to the plane while it flushes, the poll
        // loop on the tunnel thread sees `stopping` at once, and a start that races this stop
        // cannot pick up half-dead resources. Re-entering is harmless: a second call finds nulls
        // and only repeats the service bookkeeping.
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
                // A start that landed meanwhile owns the ticker, retention and foreground state.
                if (generation != tunnelGeneration) return@post
                releaseResources()
                setPersistedRunning(this@ExpressVpnService, false)
                stopForegroundCompat()
                stopSelf()
            }
        }, "diting-express-teardown").start()
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
    }

    /// The blocking half of a shutdown. Already runs off the main thread on the `fail()` path.
    private fun releaseTunnel(engine: Engine?, plane: EngineDataPlane?) {
        runCatching { engine?.stop() }
            .onFailure { Log.w(TAG, "engine.stop failed", it) }
        runCatching { engine?.releaseTun() }
        runCatching { plane?.close() }
    }

    /// Drops the resolver callbacks; no log writers are attached in this mode
    private fun closeDataPlane() {
        val plane = dataPlane
        dataPlane = null
        runCatching { plane?.close() }
    }

    private fun releaseResources() {
        runCatching { tun?.close() }
        tun = null
        worker = null
        statsTicker.stop()
        // Retention sweep is bound to the tunnel lifetime, not the process.
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
            // Stays started and in the foreground until the slot frees up; the persisted flag
            // keeps saying "the user wants this running".
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
        val notification = buildNotification(this)
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
            Log.e(TAG, "startForeground failed", t)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "极速模式",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持 DNS 窄路由 VPN 运行"
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
        private const val TAG = "ExpressVpnService"

        /// Log database of this mode (RuleDataset.EXPRESS, version 2)
        private const val LOG_DATABASE = "diting_express"

        /// Separate retention window; not shared with normal mode
        private const val LOG_PREFS = "diting_express_prefs"

        const val ACTION_START = "com.haoze.diting.express.START_VPN"
        const val ACTION_STOP = "com.haoze.diting.express.STOP_VPN"

        /// Re-applies the rule snapshot to the already-running tunnel (no drop/reconnect).
        const val ACTION_RELOAD_RULES = "com.haoze.diting.express.RELOAD_RULES"

        const val EXTRA_DNS_CONFIG = "dns_config"
        const val EXTRA_OUTBOUND_PROXY = "outbound_proxy"

        /// Package of the app that owns the loopback proxy port; excluded from the TUN.
        const val EXTRA_PROXY_APP = "proxy_app_package"
        const val EXTRA_IPV6_MODE = "ipv6_mode"
        const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"

        private const val CHANNEL_ID = "channel_express"
        private const val NOTIFICATION_ID = 2003
        internal const val PREFS_NAME = "express_vpn_prefs"
        private const val KEY_VPN_RUNNING = "express_vpn_running"
        private const val KEY_LOG_MODE = "dns_log_mode"
        private const val SETTINGS_PREFS = "diting_express_prefs"

        // Last start configuration, replayed by the quick settings tile.
        internal const val KEY_LAST_DNS_CONFIG = "last_dns_config"
        private const val KEY_LAST_OUTBOUND_PROXY = "last_outbound_proxy"
        private const val KEY_LAST_PROXY_APP = "last_outbound_proxy_app"
        private const val KEY_LAST_IPV6_MODE = "last_ipv6_mode"
        private const val KEY_LAST_EXCLUDED_PACKAGES = "last_excluded_packages"

        /// How often the tunnel thread checks whether the session it started is still running.
        private const val SESSION_POLL_MS = 200L

        @Volatile
        var isRunning: Boolean = false

        /// Epoch millis of the last successful start; 0 while stopped.
        @Volatile
        var startedAt: Long = 0L

        @Volatile
        private var activeEngine: Engine? = null

        
        internal fun engineForDiagnostics(): Engine? = activeEngine

        @Volatile
        var lastError: String? = null

        /// Displaced by another VPN and waiting to reconnect; [isRunning] is false meanwhile.
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
            // The tile lives in another UI surface; it only repaints when told to re-read.
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

        /// Builds the foreground notification from the current settings; the body prefers the
        /// user's custom text over the legacy-style line Dart composed.
        private fun buildNotification(context: Context): Notification {
            val openIntent = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val stopIntent = PendingIntent.getService(
                context,
                1,
                Intent(context, ExpressVpnService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val label = context.applicationInfo.loadLabel(context.packageManager).toString()
            val status = NotificationSettings.runningText(
                context,
                NotificationMode.EXPRESS,
                "运行中",
            )
            // No traffic monitor runs in express mode, so the speed item is left out here.
            val detail = NotificationStatsLine.compose(context, withSpeed = false)
            val body = if (detail == null) status else "$status\n$detail"
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("$label · 极速模式")
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(openIntent)
                .addAction(0, "停止", stopIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
        }

        /// Rebuilds the posted notification after a settings change; false when nothing is posted
        fun refreshNotification(context: Context): Boolean {
            if (!isRunning) return false
            return runCatching {
                val manager = context.getSystemService(NotificationManager::class.java)
                    ?: return@runCatching false
                manager.notify(NOTIFICATION_ID, buildNotification(context))
                true
            }.getOrDefault(false)
        }

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

        /// Asks a running tunnel to rebuild its rules in place. A no-op when it is not running.
        fun requestReload(context: Context) {
            if (!isRunning) return
            runCatching { context.startService(reloadIntent(context)) }
        }

        fun reloadIntent(context: Context): Intent =
            Intent(context, ExpressVpnService::class.java).setAction(ACTION_RELOAD_RULES)

        /// Rebuilds the last start intent so the tile can restart the tunnel without Dart, which
        /// is where the DNS config is computed. Null until the service was started at least once.
        fun restoreIntent(context: Context): Intent? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dnsConfig = prefs.getString(KEY_LAST_DNS_CONFIG, null)
            if (dnsConfig.isNullOrBlank()) return null
            val defaults = VpnPlanNative.startDefaults
            return startIntent(
                context = context,
                dnsConfig = dnsConfig,
                proxyJson = prefs.getString(KEY_LAST_OUTBOUND_PROXY, null)
                    ?: defaults.outboundProxy,
                ipv6Mode = prefs.getString(KEY_LAST_IPV6_MODE, null) ?: defaults.ipv6Mode,
                excludedPackages = prefs.getStringSet(KEY_LAST_EXCLUDED_PACKAGES, null)
                    .orEmpty().toList(),
                proxyAppPackage = prefs.getString(KEY_LAST_PROXY_APP, null).orEmpty(),
            )
        }
    }
}
