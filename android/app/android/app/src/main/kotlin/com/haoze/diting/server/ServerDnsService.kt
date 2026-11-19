package com.haoze.diting.server

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.tile.QuickSettingsTileUpdater
import com.haoze.diting.vpn.VpnServiceForeground
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/// Supervises the standalone Rust DNS process. Root starts through `su` on port 53; otherwise the
/// executable runs as the app UID on 1053. A 53 bind failure is reported, never silently downgraded.
class ServerDnsService : Service() {
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-server-supervisor")
    }

    @Volatile private var process: Process? = null
    @Volatile private var launching = false
    @Volatile private var stopRequested = false
    @Volatile private var readyLine: String? = null
    @Volatile private var lastError: String? = null

    override fun onCreate() {
        super.onCreate()
        VpnServiceForeground.createChannel(
            this,
            CHANNEL_ID,
            getString(R.string.server_channel_name),
            getString(R.string.server_channel_description),
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            worker.execute { stopServer(stopSelf = true) }
            return START_NOT_STICKY
        }
        if (process != null || launching) {
            return START_STICKY
        }
        stopRequested = false
        launching = true
        if (!startForegroundNow(getString(R.string.server_notification_starting))) {
            launching = false
            ServerProcessState.failed(getString(R.string.server_start_failed), false, 1053)
            publishState()
            stopSelf()
            return START_NOT_STICKY
        }
        val preferRoot = intent?.getBooleanExtra(EXTRA_PREFER_ROOT, ServerPreference.preferRoot(this))
            ?: ServerPreference.preferRoot(this)
        worker.execute { launch(preferRoot) }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRequested = true
        process?.destroy()
        worker.shutdown()
        super.onDestroy()
    }

    private fun launch(preferRoot: Boolean) {
        try {
            if (stopRequested) return
            lastError = null
            readyLine = null
            ServerProcessState.begin(preferRoot)
            publishState()
            val rootProbe = if (preferRoot) ServerRoot.probe() else RootProbeResult(false, -1, "")
            val root = preferRoot && rootProbe.available
            val port = if (root) 53 else 1053
            val binary = File(applicationInfo.nativeLibraryDir, "libditing_server.so")
            if (!binary.isFile) {
                fail(getString(R.string.server_binary_missing), root, port)
                return
            }
            binary.setExecutable(true, false)
            val dataDir = ServerPaths.dataDir(this)
            dataDir.mkdirs()
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
            val command = args.joinToString(" ") { ServerRoot.shellQuote(it) }
            val builder = if (root) {
                ProcessBuilder("su", "-c", command)
            } else {
                ProcessBuilder(args)
            }.redirectErrorStream(true)

            try {
                val child = builder.start()
                process = child
                val ready = CountDownLatch(1)
                Thread({ monitor(child, port, root, ready) }, "diting-server-log").start()
                if (!ready.await(20, TimeUnit.SECONDS)) {
                    if (process != null) {
                        fail(
                            lastError ?: getString(R.string.server_start_timeout),
                            root,
                            port,
                        )
                        stopProcess(force = true)
                    }
                }
            } catch (error: Throwable) {
                fail(
                    error.message ?: getString(R.string.server_start_failed),
                    root,
                    port,
                )
            }
        } finally {
            launching = false
        }
    }

    private fun monitor(child: Process, port: Int, root: Boolean, ready: CountDownLatch) {
        val log = ServerPaths.logFile(this)
        runCatching {
            child.inputStream.bufferedReader().forEachLine { line ->
                appendLog(log, line)
                if (line.startsWith(READY_PREFIX)) {
                    val payload = line.removePrefix(READY_PREFIX).trim()
                    readyLine = payload
                    lastError = null
                    val json = runCatching { JSONObject(payload) }.getOrNull()
                    val addresses = json?.optJSONArray("addresses")?.let { array ->
                        List(array.length()) { array.optString(it) }
                    } ?: listOf("0.0.0.0:$port")
                    val pid = json?.optLong("pid", 0L) ?: 0L
                    ServerProcessState.ready(root, port, addresses, pid)
                    updateNotification()
                    publishState()
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
        ready.countDown()
        process = null
        if (!stopRequested) {
            val message = lastError ?: getString(R.string.server_exited, exit)
            ServerProcessState.failed(message, root, port)
            publishState()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun stopServer(stopSelf: Boolean) {
        if (stopRequested) return
        stopRequested = true
        val child = process
        if (child != null) {
            runCatching {
                ServerControlSocket.request(this, "shutdown", JSONObject(), id = 0)
            }
            if (!runCatching { child.waitFor(5, TimeUnit.SECONDS) }.getOrDefault(false)) {
                stopProcess(force = true)
            }
        }
        process = null
        ServerProcessState.stopped()
        publishState()
        if (stopSelf) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun stopProcess(force: Boolean) {
        val child = process ?: return
        child.destroy()
        if (force && !child.waitFor(2, TimeUnit.SECONDS)) {
            child.destroyForcibly()
        }
    }

    private fun appendLog(file: File, line: String) {
        runCatching {
            file.parentFile?.mkdirs()
            file.appendText(line + "\n")
        }
    }

    private fun fail(message: String, root: Boolean, port: Int) {
        lastError = message
        ServerProcessState.failed(message, root, port)
        publishState()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun publishState() {
        updateNotification()
        QuickSettingsTileUpdater.requestTileUpdate(this)
    }

    private fun startForegroundNow(text: String): Boolean {
        val error = VpnServiceForeground.promote(this, NOTIFICATION_ID, buildNotification(text))
        if (error == null) return true
        Log.e(TAG, "Failed to promote server foreground notification", error)
        return false
    }

    private fun updateNotification() {
        runCatching {
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(notificationText()))
        }.onFailure { Log.w(TAG, "Failed to update server notification", it) }
    }

    private fun notificationText(): String {
        val state = ServerProcessState.snapshot()
        if (state["starting"] == true) return getString(R.string.server_notification_starting)
        if (state["running"] != true) {
            val error = state["error"] as? String
            return error ?: getString(R.string.server_notification_stopped)
        }
        val root = state["root"] as? Boolean == true
        val port = (state["port"] as? Number)?.toInt() ?: 1053
        return getString(
            if (root) R.string.server_notification_running_root
            else R.string.server_notification_running,
            port,
        )
    }

    private fun buildNotification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            10,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            11,
            Intent(this, ServerDnsService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.server_notification_title))
            .setContentText(text)
            .setContentIntent(open)
            .addAction(0, getString(R.string.server_notification_stop), stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        private const val TAG = "ServerDnsService"
        private const val CHANNEL_ID = "channel_server"
        private const val NOTIFICATION_ID = 5301
        private const val READY_PREFIX = "SERVER_READY "
        const val ACTION_START = "com.haoze.diting.server.START"
        const val ACTION_STOP = "com.haoze.diting.server.STOP"
        const val EXTRA_PREFER_ROOT = "prefer_root"

        fun start(context: Context, preferRoot: Boolean): Boolean {
            ServerPreference.setPreferRoot(context, preferRoot)
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
            val intent = Intent(context, ServerDnsService::class.java).setAction(ACTION_STOP)
            return runCatching {
                context.startService(intent)
                true
            }.getOrElse {
                Log.e(TAG, "Failed to stop server service", it)
                false
            }
        }

        fun status(): Map<String, Any?> = ServerProcessState.snapshot()
        fun isRunning(): Boolean = ServerProcessState.running || ServerProcessState.starting
    }
}
