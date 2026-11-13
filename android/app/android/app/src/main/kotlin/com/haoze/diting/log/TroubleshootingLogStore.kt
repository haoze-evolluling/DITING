package com.haoze.diting.log

import android.content.Context
import java.io.File

/// One file the troubleshooting log page can list, read, delete or share.
///
/// Runtime captures live in `getExternalFilesDir/runtime_logs`; crash reports live in the app's
/// private `filesDir/crash` plus the legacy `crash_logs`. [resolve] only accepts a bare name
/// inside those directories, so a channel caller cannot address any other file.
internal data class TroubleshootLogFile(
    val kind: String,
    val name: String,
    val file: File,
)

internal object TroubleshootingLogStore {
    const val KIND_RUNTIME = "runtime"
    const val KIND_CRASH = "crash"

    /// A crash report can be a whole tombstone; the viewer only needs its useful head.
    private const val MAX_READ_CHARS = 200_000

    private const val CRASH_DIR = "crash"
    private const val LEGACY_CRASH_DIR = "crash_logs"

    /// Both kinds in one newest-first timeline, so the page can merge them directly.
    fun list(context: Context): List<TroubleshootLogFile> {
        val runtime = (RuntimeLogStore.files(context) + RuntimeEventLog.files(context)).map {
            TroubleshootLogFile(KIND_RUNTIME, it.name, it)
        }
        val crash = crashDirs(context).flatMap { dir ->
            dir.listFiles().orEmpty()
                .filter { it.isFile }
                .map { TroubleshootLogFile(KIND_CRASH, it.name, it) }
        }
        return (runtime + crash).sortedByDescending { it.file.lastModified() }
    }

    /// `(content, truncated)`; `(null, false)` when the name does not resolve to a readable file.
    fun read(context: Context, kind: String, name: String): Pair<String?, Boolean> {
        val file = resolve(context, kind, name) ?: return null to false
        val text = runCatching { file.readText() }.getOrNull() ?: return null to false
        val truncated = text.length > MAX_READ_CHARS
        return (if (truncated) text.take(MAX_READ_CHARS) else text) to truncated
    }

    fun delete(context: Context, kind: String, name: String): Boolean =
        resolve(context, kind, name)
            ?.let { runCatching { it.delete() }.getOrDefault(false) }
            ?: false

    fun resolve(context: Context, kind: String, name: String): File? {
        if (name.isBlank() || name == "." || name == ".." ||
            name.contains('/') || name.contains('\\')
        ) {
            return null
        }
        val dirs = when (kind) {
            KIND_RUNTIME -> listOf(RuntimeLogStore.dir(context), RuntimeEventLog.dir(context))
            KIND_CRASH -> crashDirs(context)
            else -> return null
        }
        return dirs.map { File(it, name) }.firstOrNull { it.isFile }
    }

    private fun crashDirs(context: Context): List<File> = listOf(
        File(context.filesDir, CRASH_DIR),
        File(context.filesDir, LEGACY_CRASH_DIR),
    )
}
