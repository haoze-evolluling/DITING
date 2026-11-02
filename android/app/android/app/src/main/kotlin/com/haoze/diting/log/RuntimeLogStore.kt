package com.haoze.diting.log

import android.content.Context
import java.io.File

/// Files behind the manual runtime-log capture: `RuntimeLogService` appends to them and
/// `RuntimeLogBridge` reads, lists and clears them. Lives outside `filesDir` so a USB cable can
/// reach the folder; the in-app export still goes through the system save picker.
object RuntimeLogStore {
    private const val DIR = "runtime_logs"

    /// Hard cap per file, then the oldest file is dropped: a stuck loop must not fill the disk.
    const val MAX_FILE_BYTES = 2L * 1024 * 1024

    const val MAX_FILES = 3

    /// Marker for "the user turned capture on".
    ///
    /// The service runs in its own process (a capture inside the app process dies with it), so a
    /// static flag in this class would read false from the UI process. A file is the cheapest thing
    /// both processes agree on.
    private const val STATE_FILE = ".capture"

    fun dir(context: Context): File {
        val root = context.getExternalFilesDir(null) ?: context.filesDir
        return File(root, DIR).apply { mkdirs() }
    }

    /// Newest first, so [read] can join them in the reverse order for a chronological export.
    fun files(context: Context): List<File> =
        dir(context)
            .listFiles()
            ?.filter { it.isFile && it.name.endsWith(".log") }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()

    fun sizeBytes(context: Context): Long = files(context).sumOf { it.length() }

    fun markCapturing(context: Context, on: Boolean) {
        val marker = stateFile(context)
        runCatching {
            if (on) {
                if (!marker.exists()) marker.writeText(timestamp())
            } else if (marker.exists()) {
                marker.delete()
            }
        }
    }

    fun isCapturing(context: Context): Boolean = stateFile(context).exists()

    private fun stateFile(context: Context): File = File(dir(context), STATE_FILE)

    /// A fresh capture file; the timestamp keeps two sessions apart.
    fun newFile(context: Context): File {
        val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US)
            .format(java.util.Date())
        return File(dir(context), "runtime-$stamp.log")
    }

    /// Drops the oldest files beyond [MAX_FILES]; returns the surviving list.
    fun trim(context: Context): List<File> {
        val files = files(context)
        files.drop(MAX_FILES).forEach { runCatching { it.delete() } }
        return files.take(MAX_FILES)
    }

    /// Everything recorded so far, oldest first, with a header the developer can read.
    ///
    /// The crash buffer is appended even when no file exists: a capture cannot record the death of
    /// its own process, so the one crash worth having is only readable afterwards.
    fun read(context: Context): String {
        val files = files(context).reversed()
        val crash = crashTail(context.packageName)
        if (files.isEmpty() && crash.isEmpty()) return ""
        val header = buildString {
            append("=".repeat(80)).append('\n')
            append("                 DITING RUNTIME LOGS EXPORT (${files.size} FILE(S))\n")
            append("                 Exported: ").append(timestamp()).append('\n')
            append("=".repeat(80)).append("\n\n")
        }
        val sections = files.map { file ->
            buildString {
                append("---- ").append(file.name).append(" ----\n")
                append(runCatching { file.readText() }.getOrDefault("(无法读取该文件)"))
            }
        }.toMutableList()
        if (crash.isNotEmpty()) sections.add("---- 系统 crash 缓冲区 ----\n$crash")
        return header + sections.joinToString("\n\n")
    }

    fun clear(context: Context): Int {
        var removed = 0
        files(context).forEach { file -> if (runCatching { file.delete() }.getOrDefault(false)) removed++ }
        return removed
    }

    /// This app's entries in the system crash buffer (native tombstones), newest last.
    ///
    /// Empty when the buffer cannot be read, which is a device restriction rather than an error.
    private fun crashTail(packageName: String): String = runCatching {
        val process = ProcessBuilder("logcat", "-b", "crash", "-d", "-v", "time", "-t", "800")
            .redirectErrorStream(true)
            .start()
        val lines = process.inputStream.bufferedReader().use { it.readLines() }
        process.waitFor()
        CrashTail.select(lines, packageName).joinToString("\n")
    }.getOrDefault("")

    private fun timestamp(): String =
        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
            .format(java.util.Date())
}
