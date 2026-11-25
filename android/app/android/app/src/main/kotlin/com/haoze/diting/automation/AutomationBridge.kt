package com.haoze.diting.automation

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class AutomationBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val appContext: Context = context.applicationContext
    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL)
    private val mainHandler: Handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "diting-automation-bridge").apply { isDaemon = true }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "reschedule" -> executor.execute {
                val ok: Boolean =
                    runCatching { ScheduleController.syncNext(appContext) }.isSuccess
                reply(result, ok)
            }
            "runNow" -> {
                val eventType: String = call.argument<String>("eventType") ?: "manual"
                executor.execute {
                    val applied: List<String> = runCatching {
                        AutomationEngine.evaluate(appContext, eventType)
                    }.getOrDefault(emptyList())
                    reply(result, applied)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun reply(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { runCatching { result.success(value) } }
    }

    companion object {
        const val CHANNEL: String = "com.haoze.diting/automation"
    }
}
