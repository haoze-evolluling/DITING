package com.haoze.diting

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.RuleSnapshotStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class RuleIndexBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "diting-rule-index").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "refresh" -> {
                val dataset = when (call.arguments as? String) {
                    "express" -> RuleDataset.EXPRESS
                    "server" -> RuleDataset.SERVER
                    else -> RuleDataset.NORMAL
                }
                executor.execute {
                    runCatching { RuleSnapshotStore.refreshIndexes(context.applicationContext, dataset) }
                        .onFailure { Log.w("RuleIndexBridge", "refresh failed", it) }
                    // 编译结束后再回复，让 Dart 侧可以先刷新索引再通知引擎重载，
                    // 避免两条线程同时重建同一份索引。
                    mainHandler.post { runCatching { result.success(true) } }
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/rule_index"
    }
}
