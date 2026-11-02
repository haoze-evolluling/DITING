package com.haoze.diting.log

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.PrintWriter
import java.util.concurrent.atomic.AtomicLong

/// Manual runtime-log capture: while it runs, `logcat` output for the app's main process is appended
/// to [RuntimeLogStore]. It is a foreground service because a backgrounded app may not keep a plain
/// thread alive, and the persistent notification doubles as the "recording" state the user can stop
/// from outside. Nothing survives the user turning it off.
///
/// It runs in its own `:log` process (see the manifest). A capture living inside the app process
/// dies with it, so the crash that matters most — the reason the user turned capture on — was the
/// one thing it could never record: the 2026-10-31 export stopped mid-GC-thrash with no stack at
/// all. From its own process it keeps reading until the app is gone.
class RuntimeLogService : Service() {

    private val generation = AtomicLong(0)

    @Volatile
    private var worker: Thread? = null

    /// Written and read across threads; `generation` is what actually cancels a stale loop.
    @Volatile
    private var capturing = false

    /// Main process the current loop follows; a different pid means the app restarted.
    @Volatile
    private var targetPid = 0

    /// Set by the watchdog once the followed process disappears.
    @Volatile
    private var targetGone = false

    /// The running `logcat`, so a restart or a stop can unblock the reader.
    @Volatile
    private var logcat: java.lang.Process? = null

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCapture()
            return START_NOT_STICKY
        }
        promoteToForeground()
        val pid = intent?.getIntExtra(EXTRA_TARGET_PID, 0) ?: 0
        RuntimeLogStore.markCapturing(this, true)
        if (capturing && pid == targetPid) {
            Log.i(TAG, "capture already running; ignoring duplicate start")
            return START_NOT_STICKY
        }
        // A new pid (the app restarted) needs a new logcat: the old one is filtered to a dead
        // process and will never print again.
        capturing = true
        targetPid = pid
        targetGone = false
        val token = generation.incrementAndGet()
        runCatching { logcat?.destroy() }
        val thread = Thread({ captureLoop(token, pid) }, "diting-runtime-log")
        worker = thread
        thread.start()
        return START_NOT_STICKY
    }

    /// Reads until the user stops it, the app dies, or the file fills up; a rotated file restarts
    /// the read, so one long session never unbounded-grows a single file.
    private fun captureLoop(token: Long, pid: Int) {
        while (capturing && generation.get() == token) {
            val file = RuntimeLogStore.newFile(this)
            RuntimeLogStore.trim(this)
            var process: java.lang.Process? = null
            var writer: PrintWriter? = null
            var watchdog: Thread? = null
            try {
                writer = PrintWriter(file.bufferedWriter(), true)
                process = launchLogcat(pid)
                logcat = process
                watchdog = startWatchdog(token, pid, process)
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                var written = 0L
                while (capturing && generation.get() == token) {
                    val line = reader.readLine() ?: break
                    writer.println(line)
                    written += line.length.toLong() + 1
                    if (written >= RuntimeLogStore.MAX_FILE_BYTES) break
                }
            } catch (t: Throwable) {
                Log.w(TAG, "logcat capture stopped", t)
                // An exec failure would otherwise spin: back off, then retry while still on.
                runCatching { Thread.sleep(1000) }
            } finally {
                runCatching { watchdog?.interrupt() }
                if (logcat === process) logcat = null
                runCatching { process?.destroy() }
                runCatching { writer?.close() }
            }
            if (targetGone) {
                // Nothing else will arrive for a process that no longer exists, and leaving the
                // foreground notification behind would only confuse the user.
                stopCapture()
                return
            }
        }
    }

    /// Ends the loop once the followed process is gone. `logcat --pid` keeps waiting otherwise, and
    /// the capture would hold a foreground notification forever.
    private fun startWatchdog(
        token: Long,
        pid: Int,
        process: java.lang.Process,
    ): Thread? {
        if (pid <= 0) return null
        val thread = Thread({
            while (capturing && generation.get() == token) {
                runCatching { Thread.sleep(WATCH_INTERVAL_MS) }
                if (!capturing || generation.get() != token) return@Thread
                if (!File("/proc/$pid").exists()) {
                    targetGone = true
                    runCatching { process.destroy() }
                    return@Thread
                }
            }
        }, "diting-runtime-log-watch")
        thread.isDaemon = true
        thread.start()
        return thread
    }

    /// `--pid` keeps the capture to this app: less noise for the developer and a lower cost for the
    /// user, which is what the confirmation dialog promises.
    private fun launchLogcat(pid: Int): java.lang.Process {
        val attempts = buildList {
            if (pid > 0) add(arrayOf("logcat", "-v", "time", "--pid", pid.toString()))
            add(arrayOf("logcat", "-v", "time"))
        }
        var last: Throwable? = null
        for (command in attempts) {
            try {
                return ProcessBuilder(*command).redirectErrorStream(true).start()
            } catch (t: Throwable) {
                last = t
            }
        }
        throw last ?: IllegalStateException("无法启动 logcat")
    }

    private fun stopCapture() {
        capturing = false
        RuntimeLogStore.markCapturing(this, false)
        generation.incrementAndGet()
        runCatching { logcat?.destroy() }
        logcat = null
        val thread = worker
        worker = null
        runCatching { thread?.interrupt() }
        stopForegroundCompat()
        stopSelf()
    }

    override fun onDestroy() {
        capturing = false
        generation.incrementAndGet()
        runCatching { logcat?.destroy() }
        logcat = null
        runCatching { worker?.interrupt() }
        worker = null
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val notification = buildNotification()
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        }.onFailure { Log.e(TAG, "startForeground failed", it) }
    }

    private fun stopForegroundCompat() {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, RuntimeLogService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("正在抓取运行日志")
            .setContentText("仅记录谛听自身的运行日志，关闭后立即停止")
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "运行日志抓取",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "手动开启的运行日志抓取期间显示，关闭后自动消失"
                setShowBadge(false)
            },
        )
    }

    companion object {
        private const val TAG = "RuntimeLogService"
        private const val CHANNEL_ID = "channel_runtime_log"
        private const val NOTIFICATION_ID = 2003
        private const val ACTION_STOP = "com.haoze.diting.action.STOP_RUNTIME_LOG"
        private const val EXTRA_TARGET_PID = "target_pid"
        private const val WATCH_INTERVAL_MS = 1000L

        /// Starts (or re-arms) the capture for [targetPid]: the app's main process, which is the one
        /// whose logs the developer needs.
        fun start(context: Context, targetPid: Int) {
            RuntimeLogStore.markCapturing(context, true)
            val intent = Intent(context, RuntimeLogService::class.java)
                .putExtra(EXTRA_TARGET_PID, targetPid)
            runCatching { ContextCompat.startForegroundService(context, intent) }
                .onFailure {
                    RuntimeLogStore.markCapturing(context, false)
                    Log.e(TAG, "start failed", it)
                }
        }

        fun stop(context: Context) {
            RuntimeLogStore.markCapturing(context, false)
            val intent = Intent(context, RuntimeLogService::class.java).setAction(ACTION_STOP)
            // Plain `startService`: a stop never needs the foreground promotion, and asking for one
            // here would trip the "did not call startForeground" timeout when the service was not
            // running at all.
            runCatching { context.startService(intent) }
        }
    }
}
