package com.haoze.diting.platform

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.Process
import android.util.Log
import androidx.core.content.FileProvider
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.log.RuntimeLogService
import com.haoze.diting.log.RuntimeLogStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class RuntimeLogBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/runtime_log"
        private const val PREFS = "diting_runtime_log"
        private const val KEY_DETAILED = "detailed"

        fun restore(context: Context) {
            if (!RuntimeLogStore.isCapturing(context)) return
            val detailed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_DETAILED, false)
            runCatching { RuntimeLogService.start(context, Process.myPid(), detailed) }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isCapturing" -> result.success(RuntimeLogStore.isCapturing(context))
            "start" -> {
                val detailed = call.argument<Boolean>("detailed") ?: detailedMode()
                setDetailedMode(detailed)
                RuntimeLogService.start(context, Process.myPid(), detailed)
                result.success(RuntimeLogStore.isCapturing(context))
            }
            "stop" -> {
                RuntimeLogService.stop(context)
                result.success(false)
            }
            "status" -> result.success(status())
            "setMode" -> {
                val detailed = call.argument<Boolean>("detailed") ?: false
                setDetailedMode(detailed)
                if (RuntimeLogStore.isCapturing(context)) {
                    RuntimeLogService.start(context, Process.myPid(), detailed)
                }
                result.success(status())
            }
            "read" -> result.success(RuntimeLogStore.read(context))
            "readEvents" -> {
                val limit = call.argument<Int>("limit") ?: 80
                result.success(RuntimeEventLog.readRecent(limit))
            }
            "appendEvent" -> {
                appendEvent(call)
                result.success(true)
            }
            "clear" -> result.success(RuntimeLogStore.clear(context))
            "shareText" -> result.success(shareText(call))
            else -> result.notImplemented()
        }
    }

    private fun appendEvent(call: MethodCall) {
        val module = call.argument<String>("module") ?: "app"
        val event = call.argument<String>("event") ?: "?"
        val level = call.argument<Int>("level") ?: RuntimeEventLog.LEVEL_INFO
        @Suppress("UNCHECKED_CAST")
        val raw = call.argument<Map<String, Any?>>("fields")
        val fields = raw?.entries
            ?.map { it.key to (it.value?.toString() ?: "") }
            ?.toTypedArray()
            ?: emptyArray()
        RuntimeEventLog.log(level, module, event, fields)
    }

    private fun status(): Map<String, Any> = runCatching {
        val capturing = RuntimeLogStore.isCapturing(context)
        val detailed = detailedMode()
        if (capturing) RuntimeLogService.start(context, Process.myPid(), detailed)
        val events = RuntimeEventLog.files(context)
        mapOf(
            "capturing" to capturing,
            "fileCount" to RuntimeLogStore.files(context).size,
            "sizeBytes" to RuntimeLogStore.sizeBytes(context),
            "detailed" to detailed,
            "eventFiles" to events.size,
            "eventBytes" to events.sumOf { it.length() },
        )
    }.getOrElse { error ->
        Log.w("RuntimeLogBridge", "status failed", error)
        mapOf(
            "capturing" to false,
            "fileCount" to 0,
            "sizeBytes" to 0L,
            "detailed" to false,
            "eventFiles" to 0,
            "eventBytes" to 0L,
        )
    }

    private fun detailedMode(): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_DETAILED, false)

    private fun setDetailedMode(detailed: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_DETAILED, detailed).apply()
    }

    private fun shareText(call: MethodCall): Boolean = runCatching {
        val text = call.argument<String>("text") ?: return false
        val name = call.argument<String>("name")?.takeIf { it.isNotBlank() } ?: "runtime-events.txt"
        val dir = File(context.cacheDir, "troubleshooting-share").apply { mkdirs() }
        val file = File(dir, name).apply { writeText(text) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(intent, "DITING").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(chooser)
        true
    }.onFailure {
        Log.w("RuntimeLogBridge", "share text failed", it)
    }.getOrDefault(false)
}
