package com.haoze.dnssr.crash

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Manages the lifecycle of local crash log files: persistence, rotation and
 * cleanup, reading, exporting, and clearing. When the app crashes 3 times in
 * a row without a manual export, the logs are automatically backed up to the
 * system Download directory.
 */
object CrashLogManager {
    private const val TAG = "CrashLogManager"
    private const val DIR_NAME = "crash_logs"
    private const val MAX_CRASH_LOGS = 8

    private const val PREFS_NAME = "dnssr_crash_state"
    private const val KEY_CONSECUTIVE_CRASH_COUNT = "consecutive_crash_count"
    private const val KEY_HAS_MANUALLY_EXPORTED = "has_manually_exported"
    private const val KEY_LAST_CRASH_TIME = "last_crash_time"
    private const val KEY_LAST_AUTO_EXPORT_TIME = "last_auto_export_time"
    private const val KEY_PENDING_AUTO_EXPORT_NOTICE = "pending_auto_export_notice"
    private const val KEY_LAST_RECORDED_NATIVE_EXIT_TIME = "last_recorded_native_exit_time"

    private const val CONSECUTIVE_THRESHOLD = 3
    private const val CONSECUTIVE_EXPIRY_MS = 24 * 60 * 60 * 1000L // Window within which crashes count as consecutive

    fun getCrashDir(context: Context): File {
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    /**
     * Synchronously writes a crash report to a local file and forces the data
     * to disk with an fsync.
     */
    fun saveCrashReport(context: Context, reportContent: String): File? {
        return runCatching {
            val dir = getCrashDir(context)
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
            val file = File(dir, "crash_$timestamp.log")

            FileOutputStream(file).use { fos ->
                fos.write(reportContent.toByteArray(Charsets.UTF_8))
                fos.flush()
                // Ensure the data is physically written to storage
                runCatching { fos.fd.sync() }
            }

            // Prune logs beyond the retention limit
            pruneOldLogs(dir)

            file
        }.onFailure { e ->
            Log.e(TAG, "Failed to save crash report to disk", e)
        }.getOrNull()
    }

    /**
     * Called every time a crash occurs: records the consecutive-crash count and,
     * once the threshold is reached without a prior manual export, automatically
     * backs the logs up to the system Download directory.
     */
    fun onCrashOccurred(context: Context) {
        runCatching {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val lastCrashTime = prefs.getLong(KEY_LAST_CRASH_TIME, 0L)
            val currentCount = prefs.getInt(KEY_CONSECUTIVE_CRASH_COUNT, 0)
            val hasExported = prefs.getBoolean(KEY_HAS_MANUALLY_EXPORTED, false)

            val newCount = if (now - lastCrashTime > CONSECUTIVE_EXPIRY_MS) {
                1
            } else {
                currentCount + 1
            }

            // Use commit() during a crash so the count is persisted synchronously
            prefs.edit()
                .putInt(KEY_CONSECUTIVE_CRASH_COUNT, newCount)
                .putLong(KEY_LAST_CRASH_TIME, now)
                .commit()

            Log.i(TAG, "Crash occurrence recorded: count=$newCount, hasManuallyExported=$hasExported")

            // Threshold reached and the user has not manually exported crash logs yet
            if (newCount >= CONSECUTIVE_THRESHOLD && !hasExported) {
                val content = generateExportContent(context)
                if (content.isNotBlank()) {
                    val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
                    val fileName = "DNSSR-crash-auto-backup-$timestamp.txt"
                    val uri = exportToDownloads(context, fileName, content)
                    if (uri != null) {
                        Log.i(TAG, "Auto-saved crash logs to system Download: $fileName")
                        prefs.edit()
                            .putLong(KEY_LAST_AUTO_EXPORT_TIME, now)
                            .putBoolean(KEY_PENDING_AUTO_EXPORT_NOTICE, true)
                            .commit()
                    }
                }
            }
        }.onFailure { e ->
            Log.e(TAG, "Failed in onCrashOccurred handler", e)
        }
    }

    /**
     * Marks that the user exported logs manually, resetting the consecutive
     * crash counter.
     */
    fun markManuallyExported(context: Context) {
        runCatching {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_HAS_MANUALLY_EXPORTED, true)
                .putInt(KEY_CONSECUTIVE_CRASH_COUNT, 0)
                .apply()
        }
    }

    /**
     * Checks and consumes the "auto-backed-up to Downloads" notice flag.
     */
    fun consumePendingAutoExportNotice(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pending = prefs.getBoolean(KEY_PENDING_AUTO_EXPORT_NOTICE, false)
        if (pending) {
            prefs.edit().putBoolean(KEY_PENDING_AUTO_EXPORT_NOTICE, false).apply()
        }
        return pending
    }

    /**
     * Exports the log content to the system Download directory.
     */
    fun exportToDownloads(context: Context, fileName: String, content: String): Uri? {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
                resolver.openOutputStream(uri)?.use { os ->
                    os.write(content.toByteArray(Charsets.UTF_8))
                    os.flush()
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                uri
            } else {
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, fileName)
                file.writeText(content, Charsets.UTF_8)
                Uri.fromFile(file)
            }
        }.getOrElse { e ->
            Log.e(TAG, "Failed to export crash log to Downloads via MediaStore, trying direct file", e)
            runCatching {
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, fileName)
                file.writeText(content, Charsets.UTF_8)
                Uri.fromFile(file)
            }.getOrNull()
        }
    }

    /**
     * Returns all local crash log files sorted from newest to oldest.
     */
    fun getCrashLogFiles(context: Context): List<File> {
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists()) return emptyList()
        return dir.listFiles { f -> f.isFile && f.name.startsWith("crash_") && f.name.endsWith(".log") }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()
    }

    fun getCrashLogCount(context: Context): Int {
        return getCrashLogFiles(context).size
    }

    /**
     * Builds the diagnostic summary content used for exports.
     */
    fun generateExportContent(context: Context): String {
        val files = getCrashLogFiles(context)
        if (files.isEmpty()) return ""

        val sb = StringBuilder()
        sb.append("================================================================================\n")
        sb.append("                 DNSSR CRASH LOGS EXPORT (${files.size} REPORT(S))\n")
        sb.append("                 Exported: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())}\n")
        sb.append("================================================================================\n\n")

        // Index table giving developers an at-a-glance overview of every crash
        sb.append("--------------------------------------------------------------------------------\n")
        sb.append("  EXECUTIVE SUMMARY\n")
        sb.append("--------------------------------------------------------------------------------\n")
        for ((index, file) in files.withIndex()) {
            val preview = runCatching {
                file.useLines { lines ->
                    var crashType = "Unknown"
                    var timeStr = ""
                    var summary = ""
                    for (line in lines.take(120)) {
                        if (line.contains("DNSSR NATIVE CRASH REPORT")) crashType = "Native Crash"
                        if (line.contains("DNSSR CRASH REPORT")) crashType = "Java Crash"
                        if (line.startsWith("Timestamp (Local): ")) timeStr = line.removePrefix("Timestamp (Local): ").trim()
                        if (line.startsWith("Exception Class  : ")) summary = line.removePrefix("Exception Class  : ").trim()
                        if (line.startsWith("Signal: ")) summary = line.trim()
                        if (line.startsWith("Abort Message: ")) {
                            summary = line.trim()
                            break
                        }
                        if (line.startsWith("Cause: ")) {
                            summary = line.trim()
                            break
                        }
                    }
                    Triple(crashType, timeStr, summary)
                }
            }.getOrNull()

            val type = preview?.first ?: "Crash"
            val time = preview?.second?.takeIf { it.isNotBlank() } ?: SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(file.lastModified()))
            val detail = preview?.third?.takeIf { it.isNotBlank() } ?: file.name
            sb.append(String.format(Locale.US, "  [%d/%d] %-12s | %s | %s\n", index + 1, files.size, type, time, detail))
        }
        sb.append("\n")

        for ((index, file) in files.withIndex()) {
            sb.append(">>> REPORT ").append(index + 1).append("/").append(files.size)
                .append(" : ").append(file.name).append(" <<<\n\n")
            runCatching {
                sb.append(file.readText(Charsets.UTF_8))
            }.onFailure {
                sb.append("(Error reading file content: ${it.message})\n")
            }
            sb.append("\n\n")
        }

        return sb.toString()
    }

    /**
     * Inspects the system's historical process exit records (Android 11+ /
     * API 30+) for native crashes (REASON_CRASH_NATIVE) that the JVM never
     * intercepted. Any crash not yet recorded has its tombstone/trace extracted
     * and turned into a standard crash log on disk.
     */
    fun checkAndCollectNativeCrashes(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return

        runCatching {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager ?: return
            val exitInfos = am.getHistoricalProcessExitReasons(context.packageName, 0, 10)
            if (exitInfos.isEmpty()) return

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lastRecordedTime = prefs.getLong(KEY_LAST_RECORDED_NATIVE_EXIT_TIME, 0L)

            // Sort oldest to newest so crash logs are generated in chronological order
            val nativeCrashes = exitInfos
                .filter { it.reason == android.app.ApplicationExitInfo.REASON_CRASH_NATIVE && it.timestamp > lastRecordedTime }
                .sortedBy { it.timestamp }

            if (nativeCrashes.isEmpty()) return

            var maxTimestamp = lastRecordedTime
            for (exitInfo in nativeCrashes) {
                val trace = runCatching {
                    exitInfo.traceInputStream?.use { stream ->
                        TombstoneParser.parse(stream)
                    }
                }.getOrNull().orEmpty()

                val report = CrashCollector.collectNativeCrashReport(
                    context = context,
                    exitInfo = exitInfo,
                    tombstoneTrace = trace
                )

                val file = saveCrashReport(context, report)
                Log.i(TAG, "Recorded historical native crash (pid=${exitInfo.pid}, time=${exitInfo.timestamp}) to: ${file?.absolutePath}")

                onCrashOccurred(context)

                if (exitInfo.timestamp > maxTimestamp) {
                    maxTimestamp = exitInfo.timestamp
                }
            }

            if (maxTimestamp > lastRecordedTime) {
                prefs.edit().putLong(KEY_LAST_RECORDED_NATIVE_EXIT_TIME, maxTimestamp).apply()
            }
        }.onFailure { e ->
            Log.w(TAG, "Failed to check historical process exit reasons for native crash", e)
        }
    }

    /**
     * Clears all saved crash logs.
     */
    fun clearCrashLogs(context: Context): Boolean {
        runCatching {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putInt(KEY_CONSECUTIVE_CRASH_COUNT, 0)
                .putBoolean(KEY_HAS_MANUALLY_EXPORTED, false)
                .putBoolean(KEY_PENDING_AUTO_EXPORT_NOTICE, false)
                .putLong(KEY_LAST_RECORDED_NATIVE_EXIT_TIME, System.currentTimeMillis())
                .apply()
        }
        return runCatching {
            val dir = File(context.filesDir, DIR_NAME)
            if (dir.exists()) {
                dir.listFiles()?.forEach { it.delete() }
            }
            true
        }.getOrDefault(false)
    }

    private fun pruneOldLogs(dir: File) {
        runCatching {
            val files = dir.listFiles { f -> f.isFile && f.name.startsWith("crash_") && f.name.endsWith(".log") }
                ?.sortedByDescending { it.lastModified() }
                ?: return

            if (files.size > MAX_CRASH_LOGS) {
                for (i in MAX_CRASH_LOGS until files.size) {
                    files[i].delete()
                }
            }
        }
    }
}
