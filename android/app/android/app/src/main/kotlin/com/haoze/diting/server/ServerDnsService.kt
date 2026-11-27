package com.haoze.diting.server

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.R
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.VpnServiceForeground
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject

class ServerDnsService : Service() {
    private val launchWorker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-server-launch")
    }
    private val stopWorker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-server-stop")
    }
    private val generation = AtomicLong(0L)
    private val processLock = Any()

    @Volatile private var process: Process? = null
    @Volatile private var launching = false
    @Volatile private var stopRequested = false
    @Volatile private var readyLine: String? = null
    @Volatile private var lastError: String? = null
    @Volatile private var activeReadyLatch: CountDownLatch? = null
    @Volatile private var activeExitLatch: CountDownLatch? = null
    @Volatile private var restartAttempts = 0
    @Volatile private var restartPending = false

    override fun onCreate() {
        super.onCreate()
        VpnServiceForeground.createChannel(
            this,
            ServerNotification.CHANNEL_ID,
            getString(R.string.server_channel_name),
            getString(R.string.server_channel_description),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopRequested = true
            // 让排队中的自动重启失效，避免停止后又被重新拉起。
            generation.incrementAndGet()
            restartPending = false
            activeReadyLatch?.countDown()
            if (process != null || launching || ServerProcessState.active) {
                ServerProcessState.stopping()
            }
            stopWorker.execute { stopServer(stopSelf = true) }
            return START_NOT_STICKY
        }
        if (process != null || launching || restartPending) {
            return START_STICKY
        }
        if (ServerProcessState.stopping) {
            if (startForegroundNow(getString(R.string.server_notification_stopped))) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        stopRequested = false
        restartAttempts = 0
        restartPending = false
        launching = true
        val gen = generation.incrementAndGet()
        if (!startForegroundNow(getString(R.string.server_notification_starting))) {
            launching = false
            ServerProcessState.failed(getString(R.string.server_start_failed), false, 1053)
            publishState(notifyBar = false)
            stopSelf()
            return START_NOT_STICKY
        }
        val preferRoot = intent?.getBooleanExtra(EXTRA_PREFER_ROOT, ServerPreference.preferRoot(this))
            ?: ServerPreference.preferRoot(this)
        ServerProcessState.begin(preferRoot)
        launchWorker.execute { launch(preferRoot, gen) }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRequested = true
        activeReadyLatch?.countDown()
        val pid = ServerProcessState.pid
        val child = process
        if (child != null) {
            runCatching { terminateProcess(child, pid, activeExitLatch) }
        }
        launchWorker.shutdown()
        stopWorker.shutdown()
        super.onDestroy()
    }

    private sealed interface AttemptOutcome {
        data object Ready : AttemptOutcome
        data object Stopped : AttemptOutcome
        data object RootUnavailable : AttemptOutcome
        data class Failed(val message: String, val root: Boolean, val port: Int) : AttemptOutcome
    }

    private fun launch(preferRoot: Boolean, gen: Long) {
        try {
            if (stopRequested || gen != generation.get()) return
            lastError = null
            readyLine = null
            publishState(notifyBar = false)
            val binary = File(applicationInfo.nativeLibraryDir, "libditing_server.so")
            if (!binary.isFile) {
                fail(getString(R.string.server_binary_missing), preferRoot, if (preferRoot) 53 else 1053)
                return
            }
            if (!binary.canExecute()) {
                runCatching { binary.setExecutable(true, false) }
            }
            val dataDir = ServerPaths.dataDir(this)
            dataDir.mkdirs()

            val outcome = if (preferRoot) {
                when (val rootAttempt = startAttempt(binary, dataDir, root = true, gen = gen)) {
                    AttemptOutcome.RootUnavailable -> {
                        if (stopRequested || gen != generation.get()) {
                            AttemptOutcome.Stopped
                        } else {
                            ServerProcessState.begin(preferRoot = false)
                            startAttempt(binary, dataDir, root = false, gen = gen)
                        }
                    }
                    else -> rootAttempt
                }
            } else {
                startAttempt(binary, dataDir, root = false, gen = gen)
            }

            when (outcome) {
                AttemptOutcome.Ready -> Unit
                AttemptOutcome.Stopped -> finishCancelledLaunch(gen)
                AttemptOutcome.RootUnavailable -> fail(
                    lastError ?: getString(R.string.server_start_failed),
                    root = false,
                    port = 1053,
                )
                is AttemptOutcome.Failed -> {
                    if (!stopRequested && gen == generation.get()) {
                        fail(outcome.message, outcome.root, outcome.port)
                    } else {
                        finishCancelledLaunch(gen)
                    }
                }
            }
        } finally {
            restartPending = false
            launching = false
        }
    }

    private fun startAttempt(
        binary: File,
        dataDir: File,
        root: Boolean,
        gen: Long,
    ): AttemptOutcome {
        if (stopRequested || gen != generation.get()) return AttemptOutcome.Stopped
        val port = if (root) 53 else 1053
        lastError = null
        readyLine = null
        val args = mutableListOf(
            binary.absolutePath,
            "--data-dir", dataDir.absolutePath,
            "--config", ServerPaths.configFile(this).absolutePath,
            "--socket", ServerPaths.socketFile(this).absolutePath,
            "--port", port.toString(),
            "--bind", "0.0.0.0",
        )
        if (root) {
            val uid = android.os.Process.myUid()
            args += listOf("--drop-uid", uid.toString(), "--drop-gid", uid.toString())
        }
        val command = "exec " + args.joinToString(" ") { ServerRoot.shellQuote(it) }
        val builder = if (root) {
            ProcessBuilder("su", "-c", command)
        } else {
            ProcessBuilder(args)
        }.redirectErrorStream(true)

        val child = try {
            builder.start()
        } catch (error: IOException) {
            return if (root) {
                AttemptOutcome.RootUnavailable
            } else {
                AttemptOutcome.Failed(
                    error.message ?: getString(R.string.server_start_failed),
                    false,
                    port,
                )
            }
        } catch (error: Throwable) {
            return AttemptOutcome.Failed(
                error.message ?: getString(R.string.server_start_failed),
                root,
                port,
            )
        }

        val ready = CountDownLatch(1)
        val exited = CountDownLatch(1)
        synchronized(processLock) {
            if (stopRequested || gen != generation.get()) {
                runCatching { child.destroyForcibly() }
                return AttemptOutcome.Stopped
            }
            process = child
            activeReadyLatch = ready
            activeExitLatch = exited
        }

        val monitorThread = Thread(
            { monitor(child, port, root, gen, ready, exited) },
            "diting-server-log",
        )
        monitorThread.start()

        val waitSeconds = if (root) ROOT_READY_TIMEOUT_SECONDS else READY_TIMEOUT_SECONDS
        val completed = ready.await(waitSeconds, TimeUnit.SECONDS)
        if (stopRequested || gen != generation.get()) {
            terminateProcess(child, ServerProcessState.pid, exited)
            return AttemptOutcome.Stopped
        }
        if (readyLine != null) {
            return AttemptOutcome.Ready
        }
        if (!completed) {
            terminateProcess(child, ServerProcessState.pid, exited)
            return if (root && isLikelyRootRejection(lastError)) {
                AttemptOutcome.RootUnavailable
            } else {
                AttemptOutcome.Failed(
                    lastError ?: getString(R.string.server_start_timeout),
                    root,
                    port,
                )
            }
        }
        if (root && isLikelyRootRejection(lastError)) {
            return AttemptOutcome.RootUnavailable
        }
        return AttemptOutcome.Failed(
            lastError ?: getString(R.string.server_start_failed),
            root,
            port,
        )
    }

    private fun monitor(
        child: Process,
        port: Int,
        root: Boolean,
        gen: Long,
        ready: CountDownLatch,
        exited: CountDownLatch,
    ) {
        val log = ServerPaths.logFile(this)
        var reachedReady = false
        var readyAtMs = 0L
        runCatching {
            child.inputStream.bufferedReader().forEachLine { line ->
                appendLog(log, line)
                if (line.startsWith(READY_PREFIX)) {
                    val payload = line.removePrefix(READY_PREFIX).trim()
                    readyLine = payload
                    reachedReady = true
                    readyAtMs = System.currentTimeMillis()
                    lastError = null
                    val json = runCatching { JSONObject(payload) }.getOrNull()
                    val addresses = json?.optJSONArray("addresses")?.let { array ->
                        List(array.length()) { array.optString(it) }
                    } ?: listOf("0.0.0.0:$port")
                    val pid = json?.optLong("pid", 0L) ?: 0L
                    if (!stopRequested && gen == generation.get()) {
                        ServerProcessState.ready(root, port, addresses, pid)
                        publishState(notifyBar = true)
                    }
                    ready.countDown()
                } else if (
                    line.isNotBlank() &&
                    (readyLine == null ||
                        line.contains("[错误]") ||
                        line.contains("failed", ignoreCase = true))
                ) {
                    lastError = line
                }
            }
        }
        val exit = runCatching { child.waitFor() }.getOrDefault(-1)
        synchronized(processLock) {
            if (process === child) {
                process = null
                activeExitLatch = null
            }
            if (activeReadyLatch === ready) {
                activeReadyLatch = null
            }
        }
        exited.countDown()
        ready.countDown()
        if (reachedReady && !stopRequested && gen == generation.get()) {
            val message = lastError ?: getString(R.string.server_exited, exit)
            // 稳定运行过一段时间的进程再次崩溃时重新计数；短时间内反复崩溃仍受上限约束。
            if (readyAtMs > 0 &&
                System.currentTimeMillis() - readyAtMs >= RESTART_STABLE_MS
            ) {
                restartAttempts = 0
            }
            if (ServerPreference.autoRestart(this) && restartAttempts < MAX_AUTO_RESTARTS) {
                scheduleRestart(root, port, message, gen)
            } else {
                ServerProcessState.failed(message, root, port)
                publishState(notifyBar = false)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    /**
     * 进程就绪后意外退出时按指数退避自动重启。
     *
     * [launching] 在退避期间保持为 true，既阻止重复的启动请求，也让
     * [ServerProcessState.active] 继续把服务视为进行中；用户手动停止会递增
     * generation，使排队中的重启直接失效。
     */
    private fun scheduleRestart(root: Boolean, port: Int, message: String, gen: Long) {
        if (stopRequested || gen != generation.get() || restartPending) return
        restartPending = true
        launching = true
        restartAttempts += 1
        ServerProcessState.restarting(message, root, port)
        publishState(notifyBar = true)
        val delay = (RESTART_BASE_DELAY_MS shl (restartAttempts - 1))
            .coerceAtMost(RESTART_MAX_DELAY_MS)
        launchWorker.execute {
            runCatching { Thread.sleep(delay) }
            if (stopRequested || gen != generation.get()) {
                restartPending = false
                launching = false
                return@execute
            }
            launch(root, gen)
        }
    }

    private fun stopServer(stopSelf: Boolean) {
        stopRequested = true
        restartPending = false
        val child: Process?
        val exited: CountDownLatch?
        val wasReady: Boolean
        val serverPid: Long
        synchronized(processLock) {
            child = process
            exited = activeExitLatch
            wasReady = readyLine != null
            serverPid = ServerProcessState.pid
        }
        if (child != null) {
            if (wasReady) {
                runCatching {
                    ServerControlSocket.request(
                        this,
                        "shutdown",
                        JSONObject(),
                        id = 0,
                        timeoutMs = SHUTDOWN_SOCKET_TIMEOUT_MS,
                    )
                }
            }
            val gracefullyStopped = if (wasReady) {
                awaitExit(child, exited, GRACEFUL_EXIT_TIMEOUT_MS)
            } else {
                false
            }
            if (!gracefullyStopped) {
                terminateProcess(child, serverPid, exited)
            }
        }
        synchronized(processLock) {
            if (process === child) {
                process = null
                activeExitLatch = null
            }
            activeReadyLatch = null
            readyLine = null
        }
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

    private fun finishCancelledLaunch(gen: Long) {
        if (gen != generation.get()) return
        if (ServerProcessState.starting || ServerProcessState.running) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            ServerProcessState.stopped()
            publishState(notifyBar = false)
            stopSelf()
        }
    }

    private fun awaitExit(child: Process, exited: CountDownLatch?, timeoutMs: Long): Boolean {
        if (!child.isAlive) return true
        if (exited != null) {
            return runCatching { exited.await(timeoutMs, TimeUnit.MILLISECONDS) }.getOrDefault(false)
        }
        return runCatching { child.waitFor(timeoutMs, TimeUnit.MILLISECONDS) }.getOrDefault(false)
    }

    private fun terminateProcess(child: Process, serverPid: Long, exited: CountDownLatch?) {
        if (serverPid > 0L) {
            runCatching { android.os.Process.sendSignal(serverPid.toInt(), SIGTERM) }
        }
        runCatching { child.destroy() }
        if (awaitExit(child, exited, TERM_WAIT_TIMEOUT_MS)) return
        if (serverPid > 0L) {
            runCatching { android.os.Process.killProcess(serverPid.toInt()) }
        }
        runCatching { child.destroyForcibly() }
        awaitExit(child, exited, KILL_WAIT_TIMEOUT_MS)
    }

    private fun isLikelyRootRejection(error: String?): Boolean {
        if (error.isNullOrBlank()) return true
        if (error.contains("[错误]") || error.contains("[启动器]") || error.contains("53")) {
            return false
        }
        return true
    }

    private fun appendLog(file: File, line: String) {
        runCatching {
            file.parentFile?.mkdirs()
            file.appendText(line + "\n")
        }
    }

    private fun fail(message: String, root: Boolean, port: Int) {
        lastError = message
        stopForeground(STOP_FOREGROUND_REMOVE)
        ServerProcessState.failed(message, root, port)
        publishState(notifyBar = false)
        stopSelf()
    }

    private fun publishState(notifyBar: Boolean) {
        if (notifyBar) {
            updateNotification()
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

    private fun updateNotification() {
        runCatching {
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.notify(
                ServerNotification.NOTIFICATION_ID,
                ServerNotification.build(this, ServerNotification.text(this)),
            )
        }.onFailure { Log.w(TAG, "Failed to update server notification", it) }
    }

    companion object {
        private const val TAG = "ServerDnsService"
        private const val READY_PREFIX = "SERVER_READY "
        private const val SIGTERM = 15
        private const val ROOT_READY_TIMEOUT_SECONDS = 8L
        private const val READY_TIMEOUT_SECONDS = 20L
        private const val SHUTDOWN_SOCKET_TIMEOUT_MS = 800
        private const val GRACEFUL_EXIT_TIMEOUT_MS = 1_500L
        private const val TERM_WAIT_TIMEOUT_MS = 500L
        private const val KILL_WAIT_TIMEOUT_MS = 300L
        private const val MAX_AUTO_RESTARTS = 5
        private const val RESTART_BASE_DELAY_MS = 1_500L
        private const val RESTART_MAX_DELAY_MS = 30_000L
        private const val RESTART_STABLE_MS = 60_000L
        const val ACTION_START = "com.haoze.diting.server.START"
        const val ACTION_STOP = "com.haoze.diting.server.STOP"
        const val EXTRA_PREFER_ROOT = "prefer_root"

        fun start(context: Context, preferRoot: Boolean): Boolean {
            ServerPreference.setPreferRoot(context, preferRoot)
            if (ServerProcessState.stopping) {
                return false
            }
            if (!ServerProcessState.running &&
                !ServerProcessState.starting &&
                !ServerProcessState.restarting
            ) {
                ServerProcessState.begin(preferRoot)
            }
            val intent = Intent(context, ServerDnsService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PREFER_ROOT, preferRoot)
            }
            return runCatching {
                ContextCompat.startForegroundService(context, intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to start server service", it)
                ServerProcessState.failed(
                    it.message ?: context.getString(R.string.server_start_failed),
                    preferRoot,
                    if (preferRoot) 53 else 1053,
                )
                false
            }
        }

        fun stop(context: Context): Boolean {
            if (!ServerProcessState.active) {
                return true
            }
            ServerProcessState.stopping()
            val intent = Intent(context, ServerDnsService::class.java).setAction(ACTION_STOP)
            return runCatching {
                context.startService(intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to stop server service", it)
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
