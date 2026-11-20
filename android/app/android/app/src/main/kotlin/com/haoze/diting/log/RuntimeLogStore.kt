package com.haoze.diting.log

import android.content.Context
import java.io.File

object RuntimeLogStore {
    private const val DIR = "runtime_logs"

    private const val STATE_FILE = ".capture"

    fun dir(context: Context): File {
        val root = context.getExternalFilesDir(null) ?: context.filesDir
        return File(root, DIR).apply { mkdirs() }
    }

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

    fun newFile(context: Context): File {
        val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US)
            .format(java.util.Date())
        return File(dir(context), "runtime-$stamp.log")
    }

    fun trim(context: Context): List<File> {
        val index = index(context)
        val directory = dir(context)
        index.files.drop(index.keep).forEach { entry ->
            runCatching { File(directory, entry.name).delete() }
        }
        return resolve(context, index.files.take(index.keep))
    }

    fun read(context: Context): String {
        val sections = ArrayList<LogStoreSection>()
        sections.add(LogStoreSection("环境信息", RuntimeEventLog.environmentSnapshot(context)))
        index(context).files.asReversed().forEach { entry ->
            val file = File(dir(context), entry.name)
            sections.add(LogStoreSection(entry.name, runCatching { file.readText() }.getOrNull()))
        }
        RuntimeEventLog.files(context).forEach { file ->
            sections.add(LogStoreSection("运行事件/${file.name}", runCatching { file.readText() }.getOrNull()))
        }
        return LogNative.storeDocument(
            sections = sections,
            crash = crashTail(context.packageName),
            exportedAt = timestamp(),
        ).orEmpty()
    }

    fun clear(context: Context): Int {
        val removed = files(context).count { runCatching { it.delete() }.getOrDefault(false) }
        return removed + RuntimeEventLog.clear(context)
    }

    private fun index(context: Context): LogStoreIndex = LogNative.storeIndex(
        dir(context).listFiles().orEmpty()
            .filter { it.isFile }
            .map { LogStoreFile(name = it.name, lastModified = it.lastModified(), length = it.length()) },
    )

    private fun resolve(context: Context, entries: List<LogStoreFile>): List<File> {
        val directory = dir(context)
        return entries.map { File(directory, it.name) }
    }

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
