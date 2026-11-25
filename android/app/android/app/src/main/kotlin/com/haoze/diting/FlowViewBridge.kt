package com.haoze.diting

import android.content.Context
import com.haoze.diting.net.EngineAccess
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlowViewBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val appContext: Context = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> {
                val since = (call.argument<Any>("sinceSeq") as? Number)?.toLong() ?: 0L
                val limit = (call.argument<Any>("limit") as? Number)?.toLong() ?: 0L
                result.success(
                    EngineAccess.current(appContext)?.flowSnapshot(since, limit) ?: EMPTY
                )
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/flow_view"
        private const val EMPTY =
            "{\"baseSeq\":0,\"nextSeq\":0,\"total\":0,\"truncated\":false,\"sessions\":[]}"
    }
}
