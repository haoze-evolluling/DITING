package com.haoze.diting.server

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.log.BootstrapLogWriter
import com.haoze.diting.log.DnsCacheMirror
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineStats
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.RaceLogWriter
import com.haoze.diting.log.RequestStats
import com.haoze.diting.normal.SpeedTicker
import com.haoze.diting.platform.NotificationMode
import com.haoze.diting.platform.NotificationSettings
import com.haoze.diting.platform.NotificationStatsLine
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.engine.BatchLogCallback
import com.haoze.diting.engine.BootstrapLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.RaceLogCallback
import java.util.concurrent.atomic.AtomicInteger

/// LAN DNS server backed by the Rust engine (`rust/diting-engine`). `startStandalone` returns once
/// both listeners are up, so unlike the VPN path it owns no thread. Config must be applied before
/// the bind: answering the first queries with an empty rule set leaks.
///
/// Every mode runs on the same engine class, and `activeEngine` stays typed as the shared
/// `TunnelEngine` interface because the socket / VPN paths only need the diagnostics half of it.
class DitingDnsServerService : Service() {
    private var engine: Engine? = null
    private var cacheMirror: DnsCacheMirror? = null
    private val generation = AtomicInteger(0)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    /// Repaints the request counts; a no-op tick when no detail item is enabled.
    private val statsTicker = SpeedTicker(
        context = this,
        active = { isRunning },
        onTick = {
            if (NotificationSettings.hasLiveItems(this)) refreshNotification(this)
        },
    )

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onCreate() {
        super.onCreate()
        RuntimeEventLog.info("dns", "service.create")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground(intent?.getIntExtra(EXTRA_PORT, DEFAULT_PORT) ?: DEFAULT_PORT)
        if (intent?.action == ACTION_RELOAD_RULES) {
            reloadRules()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            stopEngine()
            return START_NOT_STICKY
        }
        val dnsConfig = intent?.getStringExtra(EXTRA_DNS_CONFIG)
        if (dnsConfig.isNullOrBlank()) {
            Log.w(TAG, "start intent without DNS config")
            RuntimeEventLog.warn("dns", "start.no_config")
            stopEngine()
            return START_NOT_STICKY
        }
        if (isRunning) {
            Log.i(TAG, "server already running; ignoring duplicate start")
            return START_NOT_STICKY
        }
        // Persisted so a reboot can rebuild the same intent; the extras themselves die with it.
        // Rules are not part of it: the engine snapshot is rebuilt from the rule database
        // (legacy behavior), so a persisted snapshot would only go stale after rule edits.
        rememberStartConfig(
            port = intent.getIntExtra(EXTRA_PORT, DEFAULT_PORT),
            dnsConfig = dnsConfig,
            adBlockEnabled = intent.getBooleanExtra(EXTRA_AD_BLOCK_ENABLED, false),
        )
        startEngine(
            port = intent.getIntExtra(EXTRA_PORT, DEFAULT_PORT),
            dnsConfig = dnsConfig,
            adBlockEnabled = intent.getBooleanExtra(EXTRA_AD_BLOCK_ENABLED, false),
        )
        return START_NOT_STICKY
    }

    private fun startEngine(
        port: Int,
        dnsConfig: String,
        adBlockEnabled: Boolean,
    ) {
        val token = generation.incrementAndGet()
        acquireLocks()
        Thread({
            try {
                val created = Engine()
                created.applyDNSConfig(dnsConfig)
                // Same builder as the tunnel modes: the snapshot is built in this process (never
                // through the Binder) and now also mmaps the DTRI index files of `rule-index/dns`.
                // A rejected snapshot throws and stops the service instead of serving DNS with
                // filtering silently off.
                EngineRuleLoader.apply(this, created, RuleDataset.DNS_MODE, TAG)
                created.setFilterDNS(adBlockEnabled)
                val logMode = if (
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getBoolean(KEY_LOG_QUERIES, true)
                ) {
                    DnsLogWriter.MODE_ALL
                } else {
                    DnsLogWriter.MODE_OFF
                }
                RequestStats.reset()
                created.setBatchLogCallback(object : BatchLogCallback {
                    override fun onDNSQueryBatch(jsonLogs: String) {
                        DnsLogWriter.writeBatch(
                            this@DitingDnsServerService,
                            DnsLogWriter.DB_SERVER,
                            logMode,
                            jsonLogs,
                        )
                    }
                })
                created.setRaceLogCallback(object : RaceLogCallback {
                    override fun onRaceResult(
                        queryName: String,
                        queryType: Long,
                        strategy: String,
                        providerCount: Long,
                        success: Boolean,
                        elapsedMs: Long,
                        selectedProviderID: String,
                        selectedElapsedMs: Long,
                        winnerProviderID: String,
                        winnerElapsedMs: Long,
                        fallbackUsed: Boolean,
                        fallbackSuccess: Boolean,
                        errorMessage: String,
                    ) {
                        RaceLogWriter.write(
                            this@DitingDnsServerService,
                            DnsLogWriter.DB_SERVER,
                            queryName = queryName,
                            queryType = queryType.toInt(),
                            strategy = strategy,
                            providerCount = providerCount.toInt(),
                            success = success,
                            elapsedMs = elapsedMs,
                            selectedProviderId = selectedProviderID,
                            selectedElapsedMs = selectedElapsedMs,
                            winnerProviderId = winnerProviderID,
                            winnerElapsedMs = winnerElapsedMs,
                            fallbackUsed = fallbackUsed,
                            fallbackSuccess = fallbackSuccess,
                            errorMessage = errorMessage,
                        )
                    }
                })
                created.setBootstrapLogCallback(object : BootstrapLogCallback {
                    override fun onBootstrapResult(
                        ipID: String,
                        ipName: String,
                        ip: String,
                        host: String,
                        success: Boolean,
                        elapsedMs: Long,
                        fallbackUsed: Boolean,
                        errorMessage: String,
                    ) {
                        BootstrapLogWriter.write(
                            this@DitingDnsServerService,
                            DnsLogWriter.DB_SERVER,
                            ipId = ipID,
                            ipName = ipName,
                            ip = ip,
                            host = host,
                            success = success,
                            elapsedMs = elapsedMs,
                            fallbackUsed = fallbackUsed,
                            errorMessage = errorMessage,
                        )
                    }
                })
                created.startStandalone(port.toLong())
                if (generation.get() != token) {
                    Log.i(TAG, "discarding DNS engine: stop requested during start")
                    runCatching { created.stopStandalone() }
                    runCatching { created.stop() }
                    runCatching { created.close() }
                    return@Thread
                }
                engine = created
                activeEngine = created
                // R4: replay the persisted pause / allowlist-only onto this freshly started engine.
                com.haoze.diting.control.BlockPauseLink.apply(this@DitingDnsServerService)
                isRunning = true
                // Server mode has its own log store; the sweep must target that file, and it has
                // no HTTP/traffic tables.
                LogRetention.start(
                    context = this,
                    databaseName = DnsLogWriter.DB_SERVER,
                    prefsName = PREFS_NAME,
                    includeHttpAndTraffic = false,
                )
                // Mirrored periodically: the server has no VpnService data plane to hang it on.
                cacheMirror = DnsCacheMirror(this, DnsLogWriter.DB_SERVER, created).also { it.start() }
                // Authoritative start time for the uptime figure; the UI process can be recreated.
                startedAt = System.currentTimeMillis()
                lastError = null
                setServiceActive(this, true)
                statsTicker.start()
                Log.i(TAG, "standalone DNS server listening on 0.0.0.0:$port (UDP & TCP)")
            } catch (t: Throwable) {
                Log.e(TAG, "Unable to start standalone DNS server", t)
            RuntimeEventLog.error("dns", "server.start_fail", "error" to (t.message ?: t.javaClass.simpleName))
                if (generation.get() == token) {
                    fail("DNS 服务启动失败：${t.message ?: t.javaClass.simpleName}")
                }
            }
        }, "diting-dns-server").start()
    }

    /// Rebuilds the rule snapshot and re-applies it to the running engine so a newly imported or
    /// updated subscription takes effect without dropping the DNS server. A failure keeps the
    /// previous rules instead of killing the service.
    private fun reloadRules() {
        val current = engine
        if (current == null || !isRunning) {
            Log.i(TAG, "rule reload requested but the server is not running")
            return
        }
        Thread({
            try {
                EngineRuleLoader.apply(this, current, RuleDataset.DNS_MODE, TAG)
                Log.i(TAG, "rule snapshot hot-reloaded")
            } catch (t: Throwable) {
                Log.e(TAG, "rule hot-reload failed; keeping previous rules", t)
            RuntimeEventLog.warn("dns", "rule.reload_fail", "error" to (t.message ?: t.javaClass.simpleName))
            }
        }, "diting-dns-rule-reload").start()
    }

    /// Stops the server without blocking the caller's thread for the shutdown.
    ///
    /// Closing the engine takes hundreds of ms and a service runs on the app's main thread - which
    /// is also Flutter's UI thread. Doing it inline froze the whole UI, and the power button's
    /// collapse (started by the same tap) skipped straight to its end once the thread resumed. So
    /// the engine is detached here and closed on a throwaway worker.
    private fun stopEngine() {
        // Detach first: a start that races this stop sees no engine, and the in-flight start (if
        // any) is discarded by the generation bump.
        val token = generation.incrementAndGet()
        val current = engine
        val mirror = cacheMirror
        engine = null
        activeEngine = null
        cacheMirror = null
        isRunning = false
        startedAt = 0L
        Thread({
            runCatching { mirror?.close() }
            runCatching { current?.stopStandalone() }
                .onFailure { Log.w(TAG, "stopStandalone failed", it) }
            runCatching { current?.stop() }
            // The Rust engine has no finalizer that would free it for us: release the handle here.
            runCatching { current?.close() }
            mainHandler.post {
                // A newer start (or another stop) owns the bookkeeping by now.
                if (generation.get() != token) return@post
                statsTicker.stop()
                LogRetention.stop()
                setServiceActive(this@DitingDnsServerService, false)
                releaseLocks()
                stopForegroundCompat()
                stopSelf()
            }
        }, "diting-dns-server-stop").start()
    }

    private fun fail(message: String) {
        RuntimeEventLog.error("dns", "server.fail", "message" to message)
        lastError = message
        isRunning = false
        startedAt = 0L
        activeEngine = null
        closeCacheMirror()
        LogRetention.stop()
        setServiceActive(this, false)
        releaseLocks()
        stopForegroundCompat()
        stopSelf()
    }

    override fun onDestroy() {
        RuntimeEventLog.info("dns", "service.destroy")
        generation.incrementAndGet()
        val current = engine
        engine = null
        activeEngine = null
        closeCacheMirror()
        runCatching { current?.stopStandalone() }
        runCatching { current?.stop() }
        runCatching { current?.close() }
        isRunning = false
        startedAt = 0L
        statsTicker.stop()
        LogRetention.stop()
        setServiceActive(this, false)
        releaseLocks()
        stopForegroundCompat()
        super.onDestroy()
    }

    /// Stops the periodic `dns_cache` mirror; the last snapshot stays readable by the UI
    private fun closeCacheMirror() {
        val mirror = cacheMirror
        cacheMirror = null
        runCatching { mirror?.close() }
    }

    /// Stores the running configuration so `DnsModeBootReceiver` can restart the service with the
    /// same settings; only the boolean flag survived a reboot before, so the restart had no config.
    private fun rememberStartConfig(
        port: Int,
        dnsConfig: String,
        adBlockEnabled: Boolean,
    ) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
            .putInt(KEY_LOCAL_PORT, port)
            .putString(KEY_LAST_DNS_CONFIG, dnsConfig)
            .putBoolean(KEY_LAST_AD_BLOCK_ENABLED, adBlockEnabled)
            .apply()
    }

    private fun acquireLocks() {
        runCatching {
            if (wakeLock == null) {
                val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = power?.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "Diting:DnsServerWakeLock",
                )?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            if (wifiLock == null) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wifi?.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "Diting:DnsServerWifiLock",
                )?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        }.onFailure { Log.w(TAG, "Failed to acquire power/wifi locks", it) }
    }

    private fun releaseLocks() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
        wifiLock = null
    }

    private fun promoteToForeground(port: Int) {
        val notification = buildNotification(this, port)
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
            RuntimeEventLog.error("dns", "foreground.fail", "error" to (t.message ?: t.javaClass.simpleName))
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "服务器模式",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "显示服务器模式的运行状态"
                setShowBadge(false)
            },
        )
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
        private const val TAG = "DitingDnsServerService"
        private const val CHANNEL_ID = "channel_dns_mode"
        private const val NOTIFICATION_ID = 2002
        private const val DEFAULT_PORT = 1053
        private const val PREFS_NAME = "diting_dns_mode_prefs"
        private const val KEY_SERVICE_ACTIVE = "service_active"
        private const val KEY_LOCAL_PORT = "local_listen_port"
        private const val KEY_LOG_QUERIES = "log_queries"

        // Last start configuration, replayed by DnsModeBootReceiver after a reboot.
        private const val KEY_LAST_DNS_CONFIG = "last_dns_config"
        private const val KEY_LAST_AD_BLOCK_ENABLED = "last_ad_block_enabled"

        const val ACTION_START = "com.haoze.diting.server.START"
        const val ACTION_STOP = "com.haoze.diting.server.STOP"

        /// Re-applies the rule snapshot to the already-running server (no stop/rebind).
        const val ACTION_RELOAD_RULES = "com.haoze.diting.server.RELOAD_RULES"

        const val EXTRA_PORT = "port"
        const val EXTRA_DNS_CONFIG = "dns_config"
        const val EXTRA_AD_BLOCK_ENABLED = "ad_block_enabled"

        @Volatile
        var isRunning: Boolean = false

        /// Epoch millis of the last successful start; 0 while stopped.
        @Volatile
        var startedAt: Long = 0L

        @Volatile
        private var activeEngine: Engine? = null

        /// Read-only handle for the diagnostics channel; never expose a setter
        internal fun engineForDiagnostics(): Engine? = activeEngine

        @Volatile
        var lastError: String? = null

        fun isServiceActive(context: Context): Boolean =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_SERVICE_ACTIVE, false)

        fun setServiceActive(context: Context, active: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_SERVICE_ACTIVE, active)
                .apply()
            // The tile lives in another UI surface; it only repaints when told to re-read.
            QuickSettingsTileUpdater.requestTileUpdate(context)
        }

        fun status(context: Context): Map<String, Any?> = mapOf(
            "running" to isRunning,
            "persisted" to isServiceActive(context),
            "error" to lastError,
            "startedAt" to startedAt,
            "stats" to EngineStats.snapshot(activeEngine),
            "port" to context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getInt(KEY_LOCAL_PORT, DEFAULT_PORT),
        )

        /// Builds the foreground notification from the current settings; the body prefers the
        /// user's custom text over the legacy-style upstream line Dart composed.
        private fun buildNotification(context: Context, port: Int): Notification {
            val openIntent = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val stopIntent = PendingIntent.getService(
                context,
                1,
                Intent(context, DitingDnsServerService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val label = context.applicationInfo.loadLabel(context.packageManager).toString()
            val status = NotificationSettings.runningText(
                context,
                NotificationMode.SERVER,
                "运行中 · 端口 $port",
            )
            // The server has no TUN, so there is no speed readout to show.
            val detail = NotificationStatsLine.compose(context, withSpeed = false)
            val body = if (detail == null) status else "$status\n$detail"
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("$label · 服务器模式")
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
            val port = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getInt(KEY_LOCAL_PORT, DEFAULT_PORT)
            return runCatching {
                val manager = context.getSystemService(NotificationManager::class.java)
                    ?: return@runCatching false
                manager.notify(NOTIFICATION_ID, buildNotification(context, port))
                true
            }.getOrDefault(false)
        }

        fun startIntent(
            context: Context,
            port: Int,
            dnsConfig: String,
            adBlockEnabled: Boolean,
        ): Intent = Intent(context, DitingDnsServerService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_PORT, port)
            putExtra(EXTRA_DNS_CONFIG, dnsConfig)
            putExtra(EXTRA_AD_BLOCK_ENABLED, adBlockEnabled)
        }

        fun stopIntent(context: Context): Intent =
            Intent(context, DitingDnsServerService::class.java).setAction(ACTION_STOP)

        /// Asks a running server to rebuild its rules in place. A no-op when it is not running:
        /// starting the service just to reload would post a foreground notification with no server.
        fun requestReload(context: Context) {
            if (!isRunning) return
            runCatching { context.startService(reloadIntent(context)) }
        }

        fun reloadIntent(context: Context): Intent =
            Intent(context, DitingDnsServerService::class.java).setAction(ACTION_RELOAD_RULES)

        /// Rebuilds the last start intent from preferences; null when none was ever stored,
        /// which means the service ran in a build without config persistence.
        fun restoreIntent(context: Context): Intent? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dnsConfig = prefs.getString(KEY_LAST_DNS_CONFIG, null)
            if (dnsConfig.isNullOrBlank()) return null
            return startIntent(
                context = context,
                port = prefs.getInt(KEY_LOCAL_PORT, DEFAULT_PORT),
                dnsConfig = dnsConfig,
                adBlockEnabled = prefs.getBoolean(KEY_LAST_AD_BLOCK_ENABLED, false),
            )
        }
    }
}
