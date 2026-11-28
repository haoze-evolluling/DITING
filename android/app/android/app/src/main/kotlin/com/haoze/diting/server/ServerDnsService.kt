package com.haoze.diting.server

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.Process
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.R
import com.haoze.diting.control.BlockPauseLink
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.log.DnsLogWriter
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineLogCallbacks
import com.haoze.diting.log.LogRetention
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.VpnServiceForeground
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * 服务器模式的进程内 DNS 服务。
 *
 * 与普通/简洁模式共用同一个 Rust 内核：启动 [Engine]、应用同一份 DNS 配置、
 * 装载同一套规则快照，并把日志写进服务器模式自己的日志库。对局域网提供 DNS
 * 由内核的 standalone 监听完成，不再拉起独立的 Rust 进程。
 */
class ServerDnsService : Service() {
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-server-engine").apply { isDaemon = true }
    }

    private var monitor: ScheduledExecutorService? = null
    private var monitorTask: ScheduledFuture<*>? = null

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var dataPlane: EngineDataPlane? = null

    @Volatile
    private var dnsConfig: String? = null

    @Volatile
    private var stopRequested = false

    @Volatile
    private var restartAttempts = 0

    @Volatile
    private var lastError: String? = null

    override fun onCreate() {
        super.onCreate()
        live = this
        VpnServiceForeground.createChannel(
            this,
            ServerNotification.CHANNEL_ID,
            getString(R.string.server_channel_name),
            getString(R.string.server_channel_description),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRequested = true
                worker.execute { stopInternal(stopSelf = true) }
                return START_NOT_STICKY
            }
            ACTION_RELOAD_RULES -> {
                worker.execute { reloadRules() }
                return START_NOT_STICKY
            }
            ACTION_APPLY_CONFIG -> {
                val config = intent.getStringExtra(EXTRA_DNS_CONFIG)
                if (!config.isNullOrBlank()) {
                    worker.execute { applyConfig(config) }
                }
                return START_STICKY
            }
        }

        val config = intent?.getStringExtra(EXTRA_DNS_CONFIG)
            ?.takeIf { it.isNotBlank() }
            ?: ServerPreference.lastDnsConfig(this)
        if (config.isNullOrBlank()) {
            fail(getString(R.string.server_dns_config_missing))
            return START_NOT_STICKY
        }
        if (engine != null && ServerProcessState.running) {
            worker.execute { applyConfig(config) }
            return START_STICKY
        }
        if (!startForegroundNow(ServerNotification.text(this))) {
            fail(getString(R.string.server_start_failed))
            return START_NOT_STICKY
        }
        val preferRoot = intent?.getBooleanExtra(
            EXTRA_PREFER_ROOT,
            ServerPreference.preferRoot(this),
        ) ?: ServerPreference.preferRoot(this)
        stopRequested = false
        restartAttempts = 0
        ServerProcessState.begin(preferRoot)
        ServerPreference.setPreferRoot(this, preferRoot)
        ServerPreference.setLastDnsConfig(this, config)
        worker.execute { launch(config, preferRoot) }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRequested = true
        ServerPortRedirect.clear()
        stopEngine()
        if (live === this) live = null
        worker.shutdown()
        super.onDestroy()
    }

    private fun launch(config: String, preferRoot: Boolean) {
        RuntimeEventLog.info("server", "service.start")
        try {
            if (stopRequested) {
                stopInternal(stopSelf = true)
                return
            }
            val current = Engine()
            engine = current
            configureEngine(current, config)
            if (stopRequested) {
                stopEngine()
                return
            }
            current.startStandalone(ServerPortRedirect.INTERNAL_PORT)
            val rooted = preferRoot && applyPortRedirect()
            dnsConfig = config
            ServerProcessState.ready(
                root = rooted,
                port = if (rooted) 53 else ServerPortRedirect.INTERNAL_PORT,
                addresses = listOf(
                    "0.0.0.0:${if (rooted) 53 else ServerPortRedirect.INTERNAL_PORT}",
                ),
                pid = Process.myPid().toLong(),
            )
            ServerPreference.setServerRunning(this, true)
            LogRetention.start(
                context = this,
                databaseName = RuleDataset.SERVER.logsDatabase(),
                prefsName = RuleDataset.SERVER.prefsName(),
                includeHttpAndTraffic = false,
            )
            startMonitor()
            publishState(notifyBar = true)
            Log.i(TAG, "server DNS listening on 0.0.0.0:${if (rooted) 53 else ServerPortRedirect.INTERNAL_PORT}")
        } catch (t: Throwable) {
            Log.e(TAG, "server DNS failed", t)
            RuntimeEventLog.error(
                "server",
                "service.fail",
                "error" to (t.message ?: t.javaClass.simpleName),
            )
            stopEngine()
            fail(t.message ?: getString(R.string.server_start_failed))
        }
    }

    private fun applyPortRedirect(): Boolean {
        val applied = ServerPortRedirect.apply(this, ServerPortRedirect.INTERNAL_PORT)
        if (!applied) {
            Log.w(TAG, "root 授权不可用，回退到端口 ${ServerPortRedirect.INTERNAL_PORT}")
        }
        return applied
    }

    private fun configureEngine(current: Engine, config: String) {
        current.applyDNSConfig(config)
        val logMode = DnsLogWriter.MODE_ALL
        val database = RuleDataset.SERVER.logsDatabase()
        EngineLogCallbacks.attach(current, applicationContext, database, logMode)

        val plane = EngineDataPlane(applicationContext, logMode, database)
        dataPlane = plane
        plane.attachResolvers(current)
        plane.attachBootstrap(current)
        plane.attachCacheMirror(current)

        current.setFilterDNS(true)
        current.setBlockIpv6(false)
        BlockPauseLink.applyTo(this, current)
        EngineRuleLoader.apply(this, current, RuleDataset.SERVER, TAG)
    }

    private fun applyConfig(config: String) {
        val current = engine ?: return
        if (stopRequested || !ServerProcessState.running) return
        try {
            current.applyDNSConfig(config)
            dnsConfig = config
            ServerPreference.setLastDnsConfig(this, config)
            reloadRules()
        } catch (t: Throwable) {
            Log.w(TAG, "apply DNS config failed", t)
            lastError = t.message ?: t.javaClass.simpleName
        }
    }

    private fun reloadRules() {
        val current = engine ?: return
        if (stopRequested || !ServerProcessState.running) return
        runCatching {
            EngineRuleLoader.apply(this, current, RuleDataset.SERVER, TAG)
        }.onFailure {
            Log.w(TAG, "rule reload failed; keeping previous rules", it)
            RuntimeEventLog.warn(
                "server",
                "rule.reload_fail",
                "error" to (it.message ?: it.javaClass.simpleName),
            )
        }
    }

    private fun startMonitor() {
        val scheduler = monitor ?: Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "diting-server-monitor").apply { isDaemon = true }
        }.also { monitor = it }
        monitorTask?.cancel(false)
        monitorTask = scheduler.scheduleWithFixedDelay(
            { checkEngine() },
            MONITOR_INTERVAL_MS,
            MONITOR_INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun checkEngine() {
        if (stopRequested) return
        val current = engine ?: return
        if (current.isRunning()) return
        val message = lastError ?: getString(R.string.server_engine_exited)
        if (!ServerPreference.autoRestart(this) ||
            restartAttempts >= MAX_AUTO_RESTARTS
        ) {
            stopEngine()
            fail(message)
            return
        }
        restartAttempts += 1
        val delay = (RESTART_BASE_DELAY_MS shl (restartAttempts - 1))
            .coerceAtMost(RESTART_MAX_DELAY_MS)
        val previous = ServerProcessState.snapshot()
        val previousRoot = previous["root"] == true
        val previousPort = (previous["port"] as? Number)?.toInt()
            ?: ServerPortRedirect.INTERNAL_PORT
        ServerProcessState.restarting(message, previousRoot, previousPort)
        publishState(notifyBar = true)
        val config = dnsConfig ?: ServerPreference.lastDnsConfig(this)
        if (config.isNullOrBlank()) {
            stopEngine()
            fail(message)
            return
        }
        worker.execute {
            runCatching { Thread.sleep(delay) }
            if (stopRequested) return@execute
            try {
                val next = Engine()
                engine = next
                configureEngine(next, config)
                next.startStandalone(ServerPortRedirect.INTERNAL_PORT)
                val rooted = previousRoot && applyPortRedirect()
                val port = if (rooted) 53 else ServerPortRedirect.INTERNAL_PORT
                ServerProcessState.ready(
                    root = rooted,
                    port = port,
                    addresses = listOf("0.0.0.0:$port"),
                    pid = Process.myPid().toLong(),
                )
                publishState(notifyBar = true)
            } catch (t: Throwable) {
                lastError = t.message ?: t.javaClass.simpleName
                checkEngine()
            }
        }
    }

    private fun stopInternal(stopSelf: Boolean) {
        stopRequested = true
        monitorTask?.cancel(false)
        monitorTask = null
        ServerPortRedirect.clear()
        stopEngine()
        ServerPreference.setServerRunning(this, false)
        if (stopSelf) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            ServerProcessState.stopped()
            publishState(notifyBar = false)
            stopSelf()
        } else {
            ServerProcessState.stopped()
            publishState(notifyBar = true)
        }
    }

    private fun stopEngine() {
        monitorTask?.cancel(false)
        monitorTask = null
        val plane = dataPlane
        dataPlane = null
        runCatching { plane?.close() }
        val current = engine
        engine = null
        runCatching { current?.stop() }
        dnsConfig = null
    }

    private fun fail(message: String) {
        lastError = message
        ServerPortRedirect.clear()
        stopEngine()
        stopForeground(STOP_FOREGROUND_REMOVE)
        ServerProcessState.failed(
            message,
            root = false,
            port = ServerPortRedirect.INTERNAL_PORT,
        )
        publishState(notifyBar = false)
        stopSelf()
    }

    private fun publishState(notifyBar: Boolean) {
        if (notifyBar) {
            runCatching {
                getSystemService(android.app.NotificationManager::class.java)
                    .notify(
                        ServerNotification.NOTIFICATION_ID,
                        ServerNotification.build(this, ServerNotification.text(this)),
                    )
            }.onFailure { Log.w(TAG, "Failed to update server notification", it) }
        }
        QuickSettingsTileUpdater.requestTileUpdate(this)
    }

    private fun startForegroundNow(text: String): Boolean {
        val error = VpnServiceForeground.promote(
            this,
            ServerNotification.NOTIFICATION_ID,
            ServerNotification.build(this, text),
        )
        if (error == null) return true
        Log.e(TAG, "Failed to promote server foreground notification", error)
        return false
    }

    companion object {
        private const val TAG = "ServerDnsService"
        private const val MONITOR_INTERVAL_MS = 1_000L
        private const val MAX_AUTO_RESTARTS = 5
        private const val RESTART_BASE_DELAY_MS = 1_500L
        private const val RESTART_MAX_DELAY_MS = 30_000L
        const val ACTION_START = "com.haoze.diting.server.START"
        const val ACTION_STOP = "com.haoze.diting.server.STOP"
        const val ACTION_APPLY_CONFIG = "com.haoze.diting.server.APPLY_CONFIG"
        const val ACTION_RELOAD_RULES = "com.haoze.diting.server.RELOAD_RULES"
        const val EXTRA_DNS_CONFIG = "dns_config"
        const val EXTRA_PREFER_ROOT = "prefer_root"

        @Volatile
        private var live: ServerDnsService? = null

        fun clearCache(): Boolean {
            val current = live?.engine ?: return false
            return runCatching {
                current.clearDNSCache()
                true
            }.getOrDefault(false)
        }

        fun start(context: Context, preferRoot: Boolean, dnsConfig: String?): Boolean {
            val config = dnsConfig?.takeIf { it.isNotBlank() }
                ?: ServerPreference.lastDnsConfig(context)
            if (config.isNullOrBlank()) return false
            ServerPreference.setPreferRoot(context, preferRoot)
            if (ServerProcessState.stopping) return false
            if (!ServerProcessState.running &&
                !ServerProcessState.starting &&
                !ServerProcessState.restarting
            ) {
                ServerProcessState.begin(preferRoot)
            }
            val intent = Intent(context, ServerDnsService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PREFER_ROOT, preferRoot)
                putExtra(EXTRA_DNS_CONFIG, config)
            }
            return runCatching {
                ContextCompat.startForegroundService(context, intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to start server service", it)
                ServerProcessState.failed(
                    it.message ?: context.getString(R.string.server_start_failed),
                    preferRoot,
                    if (preferRoot) 53 else ServerPortRedirect.INTERNAL_PORT,
                )
                false
            }
        }

        fun applyConfig(context: Context, dnsConfig: String): Boolean {
            if (!ServerProcessState.active) return false
            val intent = Intent(context, ServerDnsService::class.java).apply {
                action = ACTION_APPLY_CONFIG
                putExtra(EXTRA_DNS_CONFIG, dnsConfig)
            }
            return runCatching {
                context.startService(intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to apply server DNS config", it)
                false
            }
        }

        fun reloadRules(context: Context): Boolean {
            if (!ServerProcessState.running) return false
            val intent = Intent(context, ServerDnsService::class.java)
                .setAction(ACTION_RELOAD_RULES)
            return runCatching {
                context.startService(intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to reload server rules", it)
                false
            }
        }

        fun stop(context: Context): Boolean {
            if (!ServerProcessState.active) {
                ServerPortRedirect.clear()
                return true
            }
            ServerProcessState.stopping()
            val intent = Intent(context, ServerDnsService::class.java)
                .setAction(ACTION_STOP)
            return runCatching {
                context.startService(intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to stop server service", it)
                ServerPortRedirect.clear()
                ServerProcessState.stopped()
                false
            }
        }

        fun status(): Map<String, Any?> = ServerProcessState.snapshot()
        fun isRunning(): Boolean =
            ServerProcessState.running ||
                ServerProcessState.starting ||
                ServerProcessState.restarting
    }
}
