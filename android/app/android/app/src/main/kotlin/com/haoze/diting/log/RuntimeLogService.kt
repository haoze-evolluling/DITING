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
import android.os.IBinder
import android.os.Process
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

class RuntimeLogService : Service() {

    private val generation = AtomicLong(0)

    @Volatile
    private var worker: Thread? = null

    @Volatile
    private var capturing = false

    @Volatile
    private var targetPid = 0

    @Volatile
    private var detailed = false

    @Volatile
    private var targetGone = false

    @Volatile
    private var logcat: java.lang.Process? = null

    override fun onBind(intent: Intent?): IBinder? = null

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
        detailed = intent?.getBooleanExtra(EXTRA_DETAILED, false) ?: false
        RuntimeLogStore.markCapturing(this, true)
        if (capturing && pid == targetPid) {
            Log.i(TAG, "capture already running; ignoring duplicate start")
            return START_NOT_STICKY
        }
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

    private fun captureLoop(token: Long, pid: Int) {
        val plan = LogNative.capturePlan(pid, Process.myUid(), detailed)
        while (capturing && generation.get() == token) {
            val file = RuntimeLogStore.newFile(this)
            RuntimeLogStore.trim(this)
            var process: java.lang.Process? = null
            var writer: PrintWriter? = null
            var watchdog: Thread? = null
            var session = 0L
            try {
                writer = PrintWriter(file.bufferedWriter(), true)
                process = launchLogcat(plan.attempts)
                logcat = process
                watchdog = startWatchdog(token, pid, process, plan.watchIntervalMs)
                session = LogNative.captureSessionNew()
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                while (capturing && generation.get() == token) {
                    val line = reader.readLine() ?: break
                    writer.println(line)
                    if (LogNative.captureLine(session, line).rotate) break
                }
            } catch (t: Throwable) {
                Log.w(TAG, "logcat capture stopped", t)
                runCatching { Thread.sleep(1000) }
            } finally {
                runCatching { watchdog?.interrupt() }
                if (logcat === process) logcat = null
                runCatching { process?.destroy() }
                runCatching { writer?.close() }
                if (session != 0L) LogNative.captureSessionFree(session)
            }
            if (targetGone) {
                stopCapture()
                return
            }
        }
    }

    private fun startWatchdog(
        token: Long,
        pid: Int,
        process: java.lang.Process,
        intervalMs: Long,
    ): Thread? {
        if (pid <= 0) return null
        val thread = Thread({
            while (capturing && generation.get() == token) {
                runCatching { Thread.sleep(intervalMs) }
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

    private fun launchLogcat(attempts: List<List<String>>): java.lang.Process {
        var last: Throwable? = null
        for (command in attempts) {
            try {
                return ProcessBuilder(command).redirectErrorStream(true).start()
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
        release()
        stopForegroundCompat()
        stopSelf()
    }

    override fun onDestroy() {
        capturing = false
        generation.incrementAndGet()
        release()
        super.onDestroy()
    }

    private fun release() {
        runCatching { logcat?.destroy() }
        logcat = null
        val thread = worker
        worker = null
        runCatching { thread?.interrupt() }
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
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
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
        // 2003 已被简洁模式 VPN 常驻通知占用，这里改用 2004 避免跨进程覆盖。
        private const val NOTIFICATION_ID = 2004
        private const val ACTION_STOP = "com.haoze.diting.action.STOP_RUNTIME_LOG"
        private const val EXTRA_TARGET_PID = "target_pid"
        private const val EXTRA_DETAILED = "detailed"

        fun start(context: Context, targetPid: Int, detailed: Boolean = false) {
            RuntimeLogStore.markCapturing(context, true)
            val intent = Intent(context, RuntimeLogService::class.java)
                .putExtra(EXTRA_TARGET_PID, targetPid)
                .putExtra(EXTRA_DETAILED, detailed)
            runCatching { ContextCompat.startForegroundService(context, intent) }
                .onFailure {
                    RuntimeLogStore.markCapturing(context, false)
                    Log.e(TAG, "start failed", it)
                }
        }

        fun stop(context: Context) {
            RuntimeLogStore.markCapturing(context, false)
            val intent = Intent(context, RuntimeLogService::class.java).setAction(ACTION_STOP)
            runCatching { context.startService(intent) }
        }
    }
}
