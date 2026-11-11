package com.haoze.diting.log

import android.content.Context
import java.io.File

/// Files behind the manual runtime-log capture: `RuntimeLogService` appends to them and
/// `RuntimeLogBridge` reads, lists and clears them. Lives outside `filesDir` so a USB cable can
/// reach the folder; the in-app export still goes through the system save picker.
///
/// Which files count, their order, the caps and every byte of the export document live in the log
/// kernel (`rust/diting-log-core/src/store.rs`); the directory, the `File` calls and the
/// `SimpleDateFormat` stamps stay here.
object RuntimeLogStore {
    private const val DIR = "runtime_logs"

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
    fun files(context: Context): List<File> = resolve(context, index(context).files)

    fun sizeBytes(context: Context): Long = index(context).files.sumOf { it.length }

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

    /// Drops the oldest files beyond the cap; returns the surviving list.
    fun trim(context: Context): List<File> {
        val index = index(context)
        val directory = dir(context)
        index.files.drop(index.keep).forEach { entry ->
            runCatching { File(directory, entry.name).delete() }
        }
        return resolve(context, index.files.take(index.keep))
    }

    /// Everything recorded so far, oldest first, with a header the developer can read.
    ///
    /// The crash buffer is appended even when no file exists: a capture cannot record the death of
    /// its own process, so the one crash worth having is only readable afterwards.
    fun read(context: Context): String {
        // Oldest first, so the export reads chronologically.
        val sections = index(context).files.asReversed().map { entry ->
            val file = File(dir(context), entry.name)
            LogStoreSection(entry.name, runCatching { file.readText() }.getOrNull())
        }
        return LogNative.storeDocument(
            sections = sections,
            crash = crashTail(context.packageName),
            exportedAt = timestamp(),
        ).orEmpty()
    }

    fun clear(context: Context): Int {
        var removed = 0
        files(context).forEach { file -> if (runCatching { file.delete() }.getOrDefault(false)) removed++ }
        return removed
    }

    /// The capture folder as the kernel ordered it, with the trim's survivor count.
    private fun index(context: Context): LogStoreIndex = LogNative.storeIndex(
        dir(context).listFiles().orEmpty()
            .filter { it.isFile }
            .map { LogStoreFile(name = it.name, lastModified = it.lastModified(), length = it.length()) },
    )

    private fun resolve(context: Context, entries: List<LogStoreFile>): List<File> {
        val directory = dir(context)
        return entries.map { File(directory, it.name) }
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
