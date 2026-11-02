package com.haoze.diting

import android.content.Context
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.RuleSnapshotStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/// Dart-facing hook that refreshes the compiled rule tries after rule writes, the counterpart of
/// the legacy app rebuilding its rule caches inside RuleOperationWorker after every batch.
/// Calling this is an optimization, not a correctness requirement: the service recompiles
/// whenever the stamp no longer matches the database, this just moves the cost off the next start.
class RuleIndexBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "diting-rule-index").apply { isDaemon = true }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "refresh" -> {
                val dataset = when (call.arguments as? String) {
                    "express" -> RuleDataset.EXPRESS
                    "server" -> RuleDataset.DNS_MODE
                    else -> RuleDataset.NORMAL
                }
                executor.execute {
                    runCatching { RuleSnapshotStore.refreshIndexes(context.applicationContext, dataset) }
                        .onFailure { android.util.Log.w("RuleIndexBridge", "refresh failed", it) }
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/rule_index"
    }
}
