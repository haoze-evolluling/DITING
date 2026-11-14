package com.haoze.diting

import com.haoze.diting.net.EngineAccess
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Dart-facing hook for N4 (实时连接视图).
///
/// Stateless: each call asks the running engine for an incremental connection snapshot. When no
/// engine is up (or the kernel lacks the entry) it returns an empty document rather than throwing,
/// so the flow page simply shows nothing while protection is stopped.
class FlowViewBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> {
                val since = (call.argument<Any>("sinceSeq") as? Number)?.toLong() ?: 0L
                val limit = (call.argument<Any>("limit") as? Number)?.toLong() ?: 0L
                result.success(EngineAccess.current()?.flowSnapshot(since, limit) ?: EMPTY)
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
