package com.haoze.diting.platform

import android.content.Context
import java.io.File

/// Crash records and file-system caches sqflite cannot reach (it only sees `databases/`).
internal class AppStorageCleaner(private val context: Context) {

    companion object {
        /// Both must be cleared: an upgraded install still has files in the old one
        private const val CRASH_DIR = "crash"
        private const val LEGACY_CRASH_DIR = "crash_logs"

        private const val CRASH_PREFS = "diting_crash_state"

        private val CRASH_STATE_KEYS = arrayOf(
            "consecutive_crash_count",
            "has_manually_exported",
            "pending_auto_export_notice",
            "last_recorded_native_exit_time",
        )

        private const val BACKGROUND_CACHE_FILE = "custom_background_cached.png"
        private const val BACKGROUND_CACHE_TMP = "custom_background_cached.tmp"
        private const val BACKGROUND_MARKER_FILE = "custom_background_uri.txt"

        /// Must match the updater's download directory, or cleanup deletes nothing
        private const val UPDATE_DIR = "app-update"
    }

    private fun crashDir(): File = File(context.filesDir, CRASH_DIR).apply { mkdirs() }

    fun crashLogCount(): Int = crashFiles().size

    fun readCrashLogs(): String {
        val files = crashFiles()
        if (files.isEmpty()) return ""
        val header = buildString {
            append("=".repeat(80)).append('\n')
            append("                 DITING CRASH LOGS EXPORT (${files.size} REPORT(S))\n")
            append("                 Exported: ").append(timestamp()).append('\n')
            append("=".repeat(80)).append("\n\n")
        }
        val body = files.joinToString("\n\n") { file ->
            buildString {
                append("---- ").append(file.name).append(" ----\n")
                // A tombstone is hundreds of lines; a truncated read still keeps the useful head.
                append(runCatching { file.readText() }.getOrDefault("(无法读取该文件)"))
            }
        }
        return header + body
    }

    /// Reports from both directories, newest first
    private fun crashFiles(): List<File> {
        val files = mutableListOf<File>()
        for (dir in arrayOf(crashDir(), File(context.filesDir, LEGACY_CRASH_DIR))) {
            if (!dir.exists()) continue
            dir.listFiles()?.forEach { if (it.isFile) files.add(it) }
        }
        return files.sortedByDescending { it.lastModified() }
    }

    private fun timestamp(): String =
        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date())

    /// Clears the crash records and resets the streak keys, or the crash-loop threshold trips again
    fun clearCrashLogs(): Int {
        var removed = 0
        removed += deleteContents(crashDir())
        removed += deleteContents(File(context.filesDir, LEGACY_CRASH_DIR))
        runCatching {
            val prefs = context.getSharedPreferences(CRASH_PREFS, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            CRASH_STATE_KEYS.forEach { editor.remove(it) }
            editor.apply()
        }
        return removed
    }

    /// Deletes downloaded APKs, and with `includeTemp` both cache dirs; returns the count
    fun clearUpdateCache(includeTemp: Boolean): Int {
        var removed = deleteContents(File(context.filesDir, UPDATE_DIR))
        if (includeTemp) {
            removed += deleteContents(context.cacheDir)
            removed += deleteContents(context.externalCacheDir)
        }
        return removed
    }

    /// Deletes the cached wallpaper and its marker; otherwise a stale URI is re-read
    fun clearCustomBackgroundCache(): Int {
        val root = context.filesDir
        var removed = 0
        val names = arrayOf(
            BACKGROUND_CACHE_FILE,
            BACKGROUND_CACHE_TMP,
            BACKGROUND_MARKER_FILE,
        )
        for (name in names) {
            val file = File(root, name)
            if (file.exists() && file.delete()) removed++
        }
        // Per-URI copies live in `background/bg_*.png`; they must go too, or the preview survives.
        removed += deleteContents(File(root, "background"))
        return removed
    }

    private fun deleteContents(dir: File?): Int {
        if (dir == null || !dir.exists()) return 0
        var removed = 0
        dir.listFiles()?.forEach { file ->
            val ok = runCatching {
                if (file.isDirectory) file.deleteRecursively() else file.delete()
            }.getOrDefault(false)
            if (ok) removed++
        }
        return removed
    }
}
