package com.haoze.diting.log

import android.content.Context
import android.os.Build
import android.os.Process
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// The always-on "runtime events" black box: a bounded, structured record of the app's own
/// behaviour (startup milestones, service/engine lifecycle, failures, uncaught errors) that the
/// user can read *after* a problem without having had capture on.
///
/// It is deliberately tiny: the level gate and the "same event within 5 s" de-duplication live in
/// `rust/diting-log-core/src/runtime_event.rs`, so one retry storm costs a single line, and the two
/// files cap at 512 KiB each. A line is `time LEVEL module event k=v ...`, greppable and one record
/// per line. The crash/logcat capture (`RuntimeLogService`) is the on-demand detailed tier; this
/// file is the tier that is always there.
///
/// `install` is called from [com.haoze.diting.DitingApplication]; every call is wrapped so a
/// missing native library or an unwritable folder only disables the black box, never the app.
object RuntimeEventLog {
    const val LEVEL_DEBUG = 0
    const val LEVEL_INFO = 1
    const val LEVEL_WARN = 2
    const val LEVEL_ERROR = 3
    const val LEVEL_FATAL = 4

    private const val TAG = "RuntimeEventLog"
    private const val DIR = "events"
    private const val ACTIVE = "runtime-events.log"
    private const val ARCHIVE = "runtime-events.1.log"
    private const val MAX_BYTES = 512L * 1024L
    private const val DEFAULT_DEDUP_MS = 5_000L
    private const val MAX_FIELDS = 24

    private val lock = Any()
    private var appContext: Context? = null
    private var gate = 0L
    private var writer: FileWriter? = null
    private var writtenBytes = 0L
    private var minLevelTag = LEVEL_INFO
    private var installed = false

    private val timeFormat = object : ThreadLocal<SimpleDateFormat>() {
        override fun initialValue() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    }

    /// Wires the black box to the app; safe to call more than once.
    fun install(context: Context) {
        synchronized(lock) {
            if (installed) return
            appContext = context.applicationContext
            installed = true
            runCatching {
                val active = File(ensureDir(), ACTIVE)
                writtenBytes = active.length()
            }.onFailure { Log.w(TAG, "runtime event log could not initialise", it) }
        }
    }

    /// The current minimum level (the number is the kernel's level tag).
    fun minLevelTag(): Int = synchronized(lock) { minLevelTag }

    fun setMinLevelTag(tag: Int) {
        synchronized(lock) {
            minLevelTag = tag
            if (gate != 0L) runCatching { LogNative.runtimeEventSetLevel(gate, tag) }
        }
    }

    fun debug(module: String, event: String, vararg fields: Pair<String, String>) =
        log(LEVEL_DEBUG, module, event, fields)

    fun info(module: String, event: String, vararg fields: Pair<String, String>) =
        log(LEVEL_INFO, module, event, fields)

    fun warn(module: String, event: String, vararg fields: Pair<String, String>) =
        log(LEVEL_WARN, module, event, fields)

    fun error(module: String, event: String, vararg fields: Pair<String, String>) =
        log(LEVEL_ERROR, module, event, fields)

    fun fatal(module: String, event: String, vararg fields: Pair<String, String>) =
        log(LEVEL_FATAL, module, event, fields)

    /// Records one event through the kernel gate and appends the surviving line.
    fun log(
        levelTag: Int,
        module: String,
        event: String,
        fields: Array<out Pair<String, String>>,
    ) {
        if (!installed) return
        runCatching {
            synchronized(lock) {
                val now = System.currentTimeMillis()
                val handle = ensureGate()
                if (handle == 0L) {
                    appendLocked(formatFallback(levelTag, module, event, fields, now))
                    return
                }
                val answer = LogNative.runtimeEventLine(
                    handle = handle,
                    timeText = timeText(now),
                    levelTag = levelTag,
                    module = module,
                    code = event,
                    fields = fields.take(MAX_FIELDS).map { it.first to it.second },
                    nowMs = now,
                )
                if (answer.wrote) appendLocked(answer.line)
            }
        }.onFailure { Log.w(TAG, "runtime event dropped", it) }
    }

    /// The most recent [limit] event lines, oldest first; used by the troubleshooting page.
    fun readRecent(limit: Int): String = synchronized(lock) {
        val lines = ArrayList<String>()
        runCatching {
            for (name in listOf(ARCHIVE, ACTIVE)) {
                val file = File(ensureDir(), name)
                if (file.exists()) lines.addAll(file.readLines())
            }
        }
        lines.takeLast(limit.coerceAtLeast(1)).joinToString("\n")
    }

    /// The event files, oldest first, for the troubleshooting list and the export.
    fun files(context: Context): List<File> = synchronized(lock) {
        val directory = dir(context)
        listOf(ARCHIVE, ACTIVE)
            .map { File(directory, it) }
            .filter { it.exists() && it.length() > 0 }
    }

    fun dir(context: Context): File = File(RuntimeLogStore.dir(context), DIR).apply { mkdirs() }

    /// Deletes both event files; the writer is reopened on the next event.
    fun clear(context: Context): Int = synchronized(lock) {
        runCatching { writer?.close() }
        writer = null
        writtenBytes = 0
        var removed = 0
        for (name in listOf(ARCHIVE, ACTIVE)) {
            val file = File(dir(context), name)
            if (file.exists() && runCatching { file.delete() }.getOrDefault(false)) removed++
        }
        removed
    }

    /// One readable header for the export: version, system, device, process and the active tier.
    fun environmentSnapshot(context: Context): String {
        val packageName = context.packageName
        val version = runCatching {
            val info = context.packageManager.getPackageInfo(packageName, 0)
            "${info.versionName} (${info.longVersionCode})"
        }.getOrDefault("?")
        return listOf(
            "采集时间: ${timeText(System.currentTimeMillis())}",
            "应用: $packageName",
            "版本: $version",
            "系统: Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
            "机型: ${Build.MANUFACTURER} ${Build.MODEL}",
            "进程: pid=${Process.myPid()}",
            "事件级别: ${levelName(minLevelTag())}",
        ).joinToString("\n")
    }

    private fun ensureGate(): Long {
        if (gate == 0L) {
            runCatching { gate = LogNative.runtimeEventNew(minLevelTag, DEFAULT_DEDUP_MS) }
                .onFailure { Log.w(TAG, "runtime event kernel unavailable", it) }
        }
        return gate
    }

    private fun ensureDir(): File {
        val context = appContext ?: error("runtime event log is not installed")
        return dir(context)
    }

    private fun appendLocked(line: String) {
        var current = writer
        if (current == null) {
            current = FileWriter(File(ensureDir(), ACTIVE), true)
            writer = current
        }
        current.append(line).append('\n')
        current.flush()
        writtenBytes += line.toByteArray(Charsets.UTF_8).size + 1
        if (writtenBytes >= MAX_BYTES) rotateLocked()
    }

    private fun rotateLocked() {
        runCatching { writer?.close() }
        writer = null
        runCatching {
            val directory = ensureDir()
            val active = File(directory, ACTIVE)
            val archive = File(directory, ARCHIVE)
            if (archive.exists()) archive.delete()
            if (active.exists()) active.renameTo(archive)
            val reopened = FileWriter(File(directory, ACTIVE), true)
            writer = reopened
            writtenBytes = 0
        }.onFailure { Log.w(TAG, "runtime event rotate failed", it) }
    }

    /// A minimal line used only when the native kernel is unavailable, so an event is never lost.
    private fun formatFallback(
        levelTag: Int,
        module: String,
        event: String,
        fields: Array<out Pair<String, String>>,
        now: Long,
    ): String {
        val builder = StringBuilder()
        builder.append(timeText(now)).append(' ')
            .append(levelName(levelTag)).append(' ')
            .append(module.replace(' ', '_')).append(' ')
            .append(event.replace(' ', '_'))
        for ((key, value) in fields.take(MAX_FIELDS)) {
            val clean = value.replace('\n', ' ').replace('\r', ' ')
            builder.append(' ').append(key).append('=')
            if (clean.any { it.isWhitespace() || it == '=' || it == '"' }) {
                builder.append('"').append(clean.replace("\"", "\\\"")).append('"')
            } else {
                builder.append(clean)
            }
        }
        return builder.toString()
    }

    private fun timeText(now: Long): String = timeFormat.get()!!.format(Date(now))

    private fun levelName(tag: Int): String = when (tag) {
        LEVEL_DEBUG -> "DEBUG"
        LEVEL_INFO -> "INFO"
        LEVEL_WARN -> "WARN"
        LEVEL_ERROR -> "ERROR"
        LEVEL_FATAL -> "FATAL"
        else -> "INFO"
    }
}
