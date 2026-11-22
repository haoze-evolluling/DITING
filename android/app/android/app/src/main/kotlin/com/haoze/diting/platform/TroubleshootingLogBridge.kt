package com.haoze.diting.platform

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
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

class TroubleshootingLogBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/troubleshooting_logs"
        private const val SHARE_DIR = "troubleshooting-share"
        private const val MIME_TEXT = "text/plain"
        private const val TAG = "TroubleshootingLogBridge"
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
            "download" -> result.success(download(call))
            "downloadAll" -> result.success(downloadAll())
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

    private fun download(call: MethodCall): Map<String, Any?> {
        val file = TroubleshootingLogStore.resolve(
            context,
            call.argument<String>("kind").orEmpty(),
            call.argument<String>("name").orEmpty(),
        ) ?: return DownloadWrite.failed().toMap()
        val bytes = runCatching { file.readBytes() }.getOrNull()
            ?: return DownloadWrite.failed().toMap()
        return DownloadFolderWriter.write(context, file.name, MIME_TEXT, bytes).toMap()
    }

    private fun downloadAll(): Map<String, Any?> {
        var saved = 0
        var failed = 0
        TroubleshootingLogStore.list(context).forEach { entry ->
            val bytes = runCatching { entry.file.readBytes() }.getOrNull()
            val write = if (bytes == null) {
                DownloadWrite.failed()
            } else {
                DownloadFolderWriter.write(context, entry.name, MIME_TEXT, bytes)
            }
            if (write.saved) saved++ else failed++
        }
        return mapOf("saved" to saved, "failed" to failed)
    }

    private fun clearAll(): Map<String, Int> {
        val runtime = RuntimeLogStore.clear(context)
        val crash = crashStore.clearCrashLogs()
        return mapOf("runtime" to runtime, "crash" to crash)
    }

    private fun shareFiles(files: List<File>, title: String): Boolean = runCatching {
        val uris = files.map {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", it)
        }
        val clip = ClipData.newRawUri(title, uris.first())
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = MIME_TEXT
                putExtra(Intent.EXTRA_STREAM, uris.single())
                clipData = clip
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = MIME_TEXT
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList<Uri>(uris))
                clipData = clip
            }
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val chooser = Intent.createChooser(intent, title).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(chooser)
        true
    }.onFailure {
        Log.w(TAG, "share failed: ${files.joinToString { it.name }}", it)
    }.getOrDefault(false)
}
