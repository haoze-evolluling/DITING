package com.haoze.diting.platform

import android.content.Context
import android.os.Process
import android.util.Log
import com.haoze.diting.log.RuntimeLogService
import com.haoze.diting.log.RuntimeLogStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Manual runtime-log capture for troubleshooting: on/off, live state, size, export and clear.
/// Keeping it on its own channel leaves `PlatformBridge` (activity-bound, crash logs) untouched.
///
/// The capture itself runs in the `:log` process, so the state lives in [RuntimeLogStore]'s marker
/// file rather than in a static field this process cannot see.
class RuntimeLogBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/runtime_log"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isCapturing" -> result.success(RuntimeLogStore.isCapturing(context))
            "start" -> {
                RuntimeLogService.start(context, Process.myPid())
                result.success(RuntimeLogStore.isCapturing(context))
            }
            "stop" -> {
                RuntimeLogService.stop(context)
                result.success(false)
            }
            // Cheap enough for the page's resume refresh: a directory listing, not a file read.
            "status" -> result.success(status())
            "read" -> result.success(RuntimeLogStore.read(context))
            "clear" -> result.success(RuntimeLogStore.clear(context))
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> = runCatching {
        val capturing = RuntimeLogStore.isCapturing(context)
        // The marker outlives the service when the app was force-stopped, so re-arm it instead of
        // showing a switch that would silently capture nothing. A duplicate start for the pid that
        // is already followed is ignored by the service.
        if (capturing) RuntimeLogService.start(context, Process.myPid())
        mapOf(
            "capturing" to capturing,
            "fileCount" to RuntimeLogStore.files(context).size,
            "sizeBytes" to RuntimeLogStore.sizeBytes(context),
        )
    }.getOrElse { error ->
        Log.w("RuntimeLogBridge", "status failed", error)
        mapOf("capturing" to false, "fileCount" to 0, "sizeBytes" to 0L)
    }
}
