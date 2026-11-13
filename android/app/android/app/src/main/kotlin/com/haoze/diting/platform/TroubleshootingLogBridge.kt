package com.haoze.diting.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.haoze.diting.log.RuntimeLogStore
import com.haoze.diting.log.TroubleshootingLogStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Per-file management for the troubleshooting log page: list, read one, delete one, share one,
/// share everything and clear everything.
///
/// Runtime captures stay on [RuntimeLogStore]; crash reports reuse [AppStorageCleaner]'s document
/// reader and the same crash/legacy-crash directories the existing 故障排查 page already counts.
class TroubleshootingLogBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/troubleshooting_logs"
        private const val SHARE_DIR = "troubleshooting-share"
        private const val MIME_TEXT = "text/plain"
    }

    private val crashStore = AppStorageCleaner(context)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(list())
            "read" -> result.success(read(call))
            "delete" -> result.success(delete(call))
            "share" -> result.success(share(call))
            "shareAll" -> result.success(shareAll())
            "clearAll" -> result.success(clearAll())
            else -> result.notImplemented()
        }
    }

    private fun list(): Map<String, Any> = runCatching {
        val items: List<Map<String, Any>> =
            TroubleshootingLogStore.list(context).map { entry ->
                mapOf<String, Any>(
                    "kind" to entry.kind,
                    "name" to entry.name,
                    "sizeBytes" to entry.file.length(),
                    "modifiedMs" to entry.file.lastModified(),
                )
            }
        mapOf<String, Any>("items" to items)
    }.getOrElse { mapOf<String, Any>("items" to emptyList<Map<String, Any>>()) }

    private fun read(call: MethodCall): Map<String, Any?> {
        val (content, truncated) = TroubleshootingLogStore.read(
            context,
            call.argument<String>("kind").orEmpty(),
            call.argument<String>("name").orEmpty(),
        )
        return mapOf("content" to content, "truncated" to truncated)
    }

    private fun delete(call: MethodCall): Boolean = TroubleshootingLogStore.delete(
        context,
        call.argument<String>("kind").orEmpty(),
        call.argument<String>("name").orEmpty(),
    )

    private fun share(call: MethodCall): Boolean {
        val file = TroubleshootingLogStore.resolve(
            context,
            call.argument<String>("kind").orEmpty(),
            call.argument<String>("name").orEmpty(),
        ) ?: return false
        return shareFiles(listOf(file), "DITING")
    }

    /// One share per kind: the same documents "export" writes, staged in cache so the FileProvider
    /// can hand them over without touching the user's export folder.
    private fun shareAll(): Boolean = runCatching {
        val runtime = RuntimeLogStore.read(context)
        val crash = crashStore.readCrashLogs()
        val dir = File(context.cacheDir, SHARE_DIR).apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val files = mutableListOf<File>()
        if (runtime.isNotBlank()) {
            files += File(dir, "DITING-runtime-logs-$stamp.txt").apply { writeText(runtime) }
        }
        if (crash.isNotBlank()) {
            files += File(dir, "DITING-crash-logs-$stamp.txt").apply { writeText(crash) }
        }
        if (files.isEmpty()) return false
        shareFiles(files, "DITING")
    }.getOrDefault(false)

    private fun clearAll(): Map<String, Int> {
        val runtime = RuntimeLogStore.clear(context)
        val crash = crashStore.clearCrashLogs()
        return mapOf("runtime" to runtime, "crash" to crash)
    }

    private fun shareFiles(files: List<File>, title: String): Boolean = runCatching {
        val uris = files.map {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", it)
        }
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = MIME_TEXT
                putExtra(Intent.EXTRA_STREAM, uris.single())
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = MIME_TEXT
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
            }
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(
            Intent.createChooser(intent, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    }.getOrDefault(false)
}
