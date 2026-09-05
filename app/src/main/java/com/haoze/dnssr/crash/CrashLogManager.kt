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
 * 负责本地崩溃日志文件的生命周期管理：持久化、轮转清理、读取、导出与清空。
 * 支持在应用连续发生 3 次崩溃且未手动导出时，自动将日志备份至系统 Download 目录。
 */
object CrashLogManager {
    private const val TAG = "CrashLogManager"
    private const val DIR_NAME = "crash_logs"
    private const val MAX_CRASH_LOGS = 15

    private const val PREFS_NAME = "dnssr_crash_state"
    private const val KEY_CONSECUTIVE_CRASH_COUNT = "consecutive_crash_count"
    private const val KEY_HAS_MANUALLY_EXPORTED = "has_manually_exported"
    private const val KEY_LAST_CRASH_TIME = "last_crash_time"
    private const val KEY_LAST_AUTO_EXPORT_TIME = "last_auto_export_time"
    private const val KEY_PENDING_AUTO_EXPORT_NOTICE = "pending_auto_export_notice"

    private const val CONSECUTIVE_THRESHOLD = 3
    private const val CONSECUTIVE_EXPIRY_MS = 24 * 60 * 60 * 1000L // 24小时内视作连续崩溃统计区间

    fun getCrashDir(context: Context): File {
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    /**
     * 同步将崩溃报告写入本地文件，并强制刷盘（sync）。
     */
    fun saveCrashReport(context: Context, reportContent: String): File? {
        return runCatching {
            val dir = getCrashDir(context)
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
            val file = File(dir, "crash_$timestamp.log")

            FileOutputStream(file).use { fos ->
                fos.write(reportContent.toByteArray(Charsets.UTF_8))
                fos.flush()
                // 确保数据已物理写入介质
                runCatching { fos.fd.sync() }
            }

            // 清理超过保留上限的旧日志
            pruneOldLogs(dir)

            file
        }.onFailure { e ->
            Log.e(TAG, "Failed to save crash report to disk", e)
        }.getOrNull()
    }

    /**
     * 每次崩溃发生时调用：记录连续崩溃次数，并在达到阈值且未手动导出时自动备份至系统 Download 目录。
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

            // 崩溃时使用 commit 同步落盘计数
            prefs.edit()
                .putInt(KEY_CONSECUTIVE_CRASH_COUNT, newCount)
                .putLong(KEY_LAST_CRASH_TIME, now)
                .commit()

            Log.i(TAG, "Crash occurrence recorded: count=$newCount, hasManuallyExported=$hasExported")

            // 连续发生 3 次及以上，且用户尚未手动导出过崩溃日志
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
     * 用户手动导出成功后标记，重置连续崩溃计数。
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
     * 检查并消费“自动备份至下载目录”提示标志。
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
     * 将日志内容导出到系统 Download 目录。
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
     * 获取所有本地崩溃日志文件，按最新到最旧排序。
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

    fun getLatestCrashTime(context: Context): Long? {
        val files = getCrashLogFiles(context)
        return files.firstOrNull()?.lastModified()
    }

    /**
     * 生成用于导出的诊断汇总内容。
     */
    fun generateExportContent(context: Context): String {
        val files = getCrashLogFiles(context)
        if (files.isEmpty()) return ""

        val sb = StringBuilder()
        sb.append("================================================================================\n")
        sb.append("                 DNSSR CRASH LOGS EXPORT (${files.size} REPORT(S))\n")
        sb.append("                 Exported: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())}\n")
        sb.append("================================================================================\n\n")

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
     * 清空所有已保存的崩溃日志。
     */
    fun clearCrashLogs(context: Context): Boolean {
        runCatching {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putInt(KEY_CONSECUTIVE_CRASH_COUNT, 0)
                .putBoolean(KEY_HAS_MANUALLY_EXPORTED, false)
                .putBoolean(KEY_PENDING_AUTO_EXPORT_NOTICE, false)
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
