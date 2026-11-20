package com.haoze.diting.root

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.Process
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.control.BlockPauseLink
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.StorageGate
import com.haoze.diting.engine.Engine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineLogCallbacks
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.server.ServerRoot
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.VpnServiceForeground
import java.util.concurrent.Executors

/// Normal mode without `VpnService`: a foreground service that runs the engine's standalone DNS
/// server on a high loopback port and makes root redirect every local port-53 query to it.
///
/// The engine runs as the app UID, so it does not need root itself; root is only used for the
/// iptables chains, Private DNS and the cache flush. Stopping removes the chains before the
/// listener goes away, so a stop can never leave the device with a dead DNS route.
class RootDnsService : Service() {
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-root-dns")
    }

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var dataPlane: EngineDataPlane? = null

    @Volatile
    private var stopRequested = false

    @Volatile
    private var lastError: String? = null

    override fun onCreate() {
        super.onCreate()
        VpnServiceForeground.createChannel(
            this,
            CHANNEL_ID,
            getString(R.string.root_dns_channel_name),
            getString(R.string.root_dns_channel_description),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                // Set before queueing: a launch already on the worker stops at its next checkpoint
                // instead of finishing a takeover the user just cancelled.
                stopRequested = true
                worker.execute { stopAll(stopSelf = true) }
                return START_NOT_STICKY
            }
            ACTION_RELOAD_RULES -> {
                worker.execute { reloadRules() }
                return START_NOT_STICKY
            }
        }
        // The platform requires startForeground within 5 s of a startForegroundService call, so
        // every failure path below has already promoted. Re-promoting a running service only
        // repaints the same notification.
        if (!promoteToForeground(notificationText())) {
            fail(getString(R.string.root_dns_start_failed))
            return START_NOT_STICKY
        }
        if (RootDnsRuntime.running || RootDnsRuntime.starting) {
            return START_STICKY
        }
        if (StorageGate.blocksDataPlane(this)) {
            Log.w(TAG, "storage upgrade in progress; refusing to start")
            fail(getString(R.string.root_dns_storage_busy))
            return START_NOT_STICKY
        }
        val dnsConfig = intent?.getStringExtra(EXTRA_DNS_CONFIG)
            ?.takeIf { it.isNotBlank() }
            ?: lastDnsConfig(this)
        if (dnsConfig.isNullOrBlank()) {
            fail(getString(R.string.root_dns_missing_config))
            return START_NOT_STICKY
        }
        stopRequested = false
        RootDnsRuntime.begin()
        rememberDnsConfig(this, dnsConfig)
        worker.execute { launch(dnsConfig) }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        // Root cleanup has to happen before the process can be reclaimed: a redirect left behind
        // points every DNS query at a port nothing listens on.
        runCatching { stopInternal() }
        // No join: the process may be reclaimed at any time, and a cold start repairs a rule set
        // a killed teardown left behind.
        worker.shutdown()
        super.onDestroy()
    }

    private fun launch(dnsConfig: String) {
        RuntimeEventLog.info("root_dns", "service.start")
        RootDnsRuntime.starting = true
        publishState()
        if (stopRequested) {
            stopInternal()
            return
        }
        val probe = ServerRoot.probe()
        if (!probe.available) {
            fail(probe.message.ifBlank { getString(R.string.root_dns_no_root) })
            return
        }
        if (DitingVpnService.isRunning || ExpressVpnService.isRunning) {
            // Both modes own the same DNS path; running them together would redirect the tunnel's
            // own resolver and leave the engine feeding answers to a dead listener.
            fail(getString(R.string.root_dns_vpn_running))
            return
        }
        if (stopRequested) {
            stopInternal()
            return
        }
        try {
            // A previous run may have died without its onDestroy. The chains are ours, so they are
            // rebuilt from scratch below; removing them first also releases a stale port forward.
            RootDnsRules.removeAll()

            val current = Engine()
            engine = current
            RootDnsRuntime.engine = current
            configureEngine(current, dnsConfig)
            if (stopRequested) {
                stopInternal()
                return
            }

            val port = startServer(current)
            RootDnsRuntime.markRulesInstalled(this, true)
            val ruleError = RootDnsRules.install(this, port, Process.myUid())
            if (ruleError != null) {
                throw IllegalStateException(ruleError)
            }
            if (!RootDnsRules.disablePrivateDns(this)) {
                // Port 53 is still redirected; only Private DNS (DoT on 853) can bypass it.
                Log.w(TAG, "Private DNS left unchanged; DoT clients may bypass the takeover")
            }
            RootDnsRules.flushCaches()

            RootDnsRuntime.ready(current, port)
            setPersistedRunning(this, true)
            LogRetention.start(
                context = this,
                databaseName = RuleDataset.NORMAL.logsDatabase(),
                prefsName = RuleDataset.NORMAL.prefsName(),
                includeHttpAndTraffic = false,
            )
            publishState()
            Log.i(TAG, "root DNS takeover running on 127.0.0.1:$port")
        } catch (t: Throwable) {
            Log.e(TAG, "root DNS takeover failed", t)
            RuntimeEventLog.error(
                "root_dns",
                "service.fail",
                "error" to (t.message ?: t.javaClass.simpleName),
            )
            fail(t.message ?: getString(R.string.root_dns_start_failed))
        }
    }

    private fun configureEngine(current: Engine, dnsConfig: String) {
        current.applyDNSConfig(dnsConfig)
        val logMode = getSharedPreferences(RuleDataset.NORMAL.prefsName(), MODE_PRIVATE)
            .getString(KEY_LOG_MODE, DnsLogWriter.MODE_ALL)
            ?: DnsLogWriter.MODE_ALL
        val database = RuleDataset.NORMAL.logsDatabase()
        EngineLogCallbacks.attach(current, applicationContext, database, logMode)

        val plane = EngineDataPlane(applicationContext, logMode, database)
        dataPlane = plane
        plane.attachResolvers(current)
        plane.attachBootstrap(current)
        plane.attachCacheMirror(current)

        current.setFilterDNS(true)
        // Root mode is not a TUN: AAAA answers remain valid, so do not suppress them.
        current.setBlockIpv6(false)
        // Same pause / allowlist-only values every other mode replays after start.
        BlockPauseLink.applyTo(this, current)
        EngineRuleLoader.apply(this, current, RuleDataset.NORMAL, TAG)
    }

    /// Binds the standalone DNS server, trying the preferred ports in order.
    ///
    /// Loopback only: the redirect target is `127.0.0.1:<port>`, and a reply from any other local
    /// address would fail the client's connected-socket source check before conntrack can undo
    /// the redirect.
    private fun startServer(current: Engine): Int {
        var lastError = ""
        for (port in PORTS) {
            val error = runCatching {
                current.startStandaloneLoopback(port)
                null
            }.getOrElse { it.message ?: it.javaClass.simpleName }
            if (error == null) return port
            lastError = error
        }
        throw IllegalStateException(lastError.ifBlank { getString(R.string.root_dns_bind_failed) })
    }

    private fun reloadRules() {
        val current = engine ?: return
        if (!RootDnsRuntime.running) return
        runCatching {
            EngineRuleLoader.apply(this, current, RuleDataset.NORMAL, TAG)
            Log.i(TAG, "rule snapshot hot-reloaded")
        }.onFailure {
            Log.w(TAG, "rule hot-reload failed; keeping previous rules", it)
            RuntimeEventLog.warn(
                "root_dns",
                "rule.reload_fail",
                "error" to (it.message ?: it.javaClass.simpleName),
            )
        }
    }

    /// Stops the service in response to a stop action or a stopSelf; idempotent.
    private fun stopAll(stopSelf: Boolean) {
        stopRequested = true
        stopInternal()
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (stopSelf) stopSelf()
    }

    @Synchronized
    private fun stopInternal() {
        stopRequested = true
        val hadRules = RootDnsRuntime.rulesInstalled(this)
        if (hadRules) {
            // Chains and Private DNS go first: until they are gone, redirecting to a listener that
            // is about to close would fail every query.
            if (RootDnsRules.teardown(this)) {
                RootDnsRuntime.markRulesInstalled(this, false)
            }
        } else {
            RootDnsRules.restorePrivateDns(this)
        }
        releaseEngine()
        RootDnsRuntime.stopped()
        RootDnsTraffic.reset()
        LogRetention.stop()
        setPersistedRunning(this, false)
        publishState()
        RuntimeEventLog.info("root_dns", "service.stop")
    }

    private fun releaseEngine() {
        val current = engine
        val plane = dataPlane
        engine = null
        dataPlane = null
        RootDnsRuntime.engine = null
        runCatching { current?.flushLogs() }
        runCatching { current?.stop() }
        runCatching { plane?.close() }
        runCatching { current?.close() }
    }

    private fun fail(message: String) {
        lastError = message
        RootDnsRuntime.failed(message)
        if (RootDnsRuntime.rulesInstalled(this)) {
            if (RootDnsRules.teardown(this)) {
                RootDnsRuntime.markRulesInstalled(this, false)
            }
        } else {
            RootDnsRules.restorePrivateDns(this)
        }
        releaseEngine()
        RootDnsTraffic.reset()
        LogRetention.stop()
        setPersistedRunning(this, false)
        publishState()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun publishState() {
        updateNotification()
        QuickSettingsTileUpdater.requestTileUpdate(this)
    }

    private fun promoteToForeground(text: String): Boolean {
        val error = VpnServiceForeground.promote(this, NOTIFICATION_ID, buildNotification(text))
        if (error == null) return true
        Log.e(TAG, "Failed to promote the root DNS notification", error)
        return false
    }

    private fun updateNotification() {
        runCatching {
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(notificationText()))
        }.onFailure { Log.w(TAG, "Failed to update the root DNS notification", it) }
    }

    private fun notificationText(): String {
        if (RootDnsRuntime.starting) return getString(R.string.root_dns_notification_starting)
        if (!RootDnsRuntime.running) {
            return RootDnsRuntime.error
                ?: lastError
                ?: getString(R.string.root_dns_notification_stopped)
        }
        return getString(R.string.root_dns_notification_running, RootDnsRuntime.port)
    }

    private fun buildNotification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            30,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            31,
            Intent(this, RootDnsService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.root_dns_notification_title))
            .setContentText(text)
            .setContentIntent(open)
            .addAction(0, getString(R.string.root_dns_notification_stop), stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        private const val TAG = "RootDnsService"
        private const val CHANNEL_ID = "diting_root_dns"
        private const val NOTIFICATION_ID = 5302
        private const val KEY_LOG_MODE = "dns_log_mode"

        /// Preferred listener ports; the first one that binds wins. Deliberately not 53: the
        /// engine runs as the app UID, and root only owns the redirect into this port.
        private val PORTS = intArrayOf(15353, 15354, 15355, 15356)

        const val ACTION_START = "com.haoze.diting.root.START"
        const val ACTION_STOP = "com.haoze.diting.root.STOP"
        const val ACTION_RELOAD_RULES = "com.haoze.diting.root.RELOAD_RULES"
        const val EXTRA_DNS_CONFIG = "dns_config"

        internal const val PREFS_NAME = RootDnsRuntime.PREFS_NAME
        private const val KEY_LAST_DNS_CONFIG = "last_dns_config"

        val isRunning: Boolean get() = RootDnsRuntime.running

        fun status(context: Context): Map<String, Any?> = RootDnsRuntime.status(context)

        fun engineForDiagnostics(): Engine? = RootDnsRuntime.engine

        fun start(context: Context, dnsConfig: String): Boolean {
            rememberDnsConfig(context, dnsConfig)
            return runCatching {
                ContextCompat.startForegroundService(context, startIntent(context, dnsConfig))
                true
            }.getOrElse {
                Log.e(TAG, "Failed to start root DNS takeover", it)
                RootDnsRuntime.failed(it.message ?: context.getString(R.string.root_dns_start_failed))
                false
            }
        }

        fun stop(context: Context): Boolean = runCatching {
            context.startService(stopIntent(context))
            true
        }.getOrElse {
            Log.e(TAG, "Failed to stop root DNS takeover", it)
            false
        }

        fun startIntent(context: Context, dnsConfig: String): Intent =
            Intent(context, RootDnsService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_DNS_CONFIG, dnsConfig)
            }

        fun stopIntent(context: Context): Intent =
            Intent(context, RootDnsService::class.java).setAction(ACTION_STOP)

        /// Rebuilds the last start intent for the quick settings tile and the widget.
        fun restoreIntent(context: Context): Intent? {
            val dnsConfig = lastDnsConfig(context) ?: return null
            return startIntent(context, dnsConfig)
        }

        fun requestReload(context: Context) {
            if (!isRunning) return
            runCatching {
                context.startService(
                    Intent(context, RootDnsService::class.java).setAction(ACTION_RELOAD_RULES),
                )
            }
        }

        /// Null on success, otherwise the reason to show.
        fun applyDnsConfig(context: Context, dnsConfig: String): String? {
            if (dnsConfig.isBlank()) return "缺少 DNS 配置"
            val current = RootDnsRuntime.engine ?: return "服务未运行"
            return runCatching {
                current.applyDNSConfig(dnsConfig)
                rememberDnsConfig(context, dnsConfig)
                null
            }.getOrElse { it.message ?: it.javaClass.simpleName }
        }

        private fun rememberDnsConfig(context: Context, dnsConfig: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LAST_DNS_CONFIG, dnsConfig)
                .apply()
        }

        private fun lastDnsConfig(context: Context): String? =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_LAST_DNS_CONFIG, null)
                ?.takeIf { it.isNotBlank() }

        fun setPersistedRunning(context: Context, value: Boolean) =
            RootDnsRuntime.setPersistedRunning(context, value)

        /// Cold-start repair: a crash between install and teardown leaves the redirect pointing at
        /// a dead listener, which breaks DNS for the whole device until it is removed.
        fun reconcileStaleRules(context: Context) {
            if (!RootDnsRuntime.rulesInstalled(context)) return
            if (RootDnsRuntime.running || RootDnsRuntime.starting) return
            Thread({
                if (RootDnsRules.teardown(context)) {
                    RootDnsRuntime.markRulesInstalled(context, false)
                }
                RootDnsRuntime.setPersistedRunning(context, false)
            }, "root-dns-reconcile").apply { isDaemon = true }.start()
        }
    }
}
