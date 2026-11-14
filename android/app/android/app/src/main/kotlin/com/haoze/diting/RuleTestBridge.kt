package com.haoze.diting

import android.content.Context
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.RuleSnapshotStore
import com.haoze.diting.engine.RuleTestNative
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * Dart-facing hook for the rule-test simulator (R1).
 *
 * The rule snapshot is built here, in the same process the engine uses, from the same
 * `RuleSnapshotStore` document the engine is fed, so the simulator's verdict cannot drift from the
 * engine's. The heavy work (packing rows, mmap tries, building the snapshot, the seven-level walk)
 * runs on the executor; only the JSON is handed back to Dart.
 */
class RuleTestBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "diting-rule-test").apply { isDaemon = true }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "check" -> check(call, result)
            else -> result.notImplemented()
        }
    }

    private fun check(call: MethodCall, result: MethodChannel.Result) {
        val domain = call.argument<String>("domain")?.trim().orEmpty()
        if (domain.isEmpty()) {
            result.error("invalid_domain", "domain required", null)
            return
        }
        val app = call.argument<String>("app")?.trim().orEmpty()
        val qtype = (call.argument<Any>("qtype") as? Number)?.toInt() ?: 1
        val dataset = when (call.argument<String>("dataset")) {
            "express" -> RuleDataset.EXPRESS
            "server" -> RuleDataset.DNS_MODE
            else -> RuleDataset.NORMAL
        }
        executor.execute {
            runCatching {
                val snapshot = RuleSnapshotStore.buildSnapshotJson(context.applicationContext, dataset)
                val rewrite = RuleSnapshotStore.buildRewriteRulesJson(context.applicationContext, dataset)
                val answer = JSONObject(RuleTestNative.check(snapshot, rewrite, domain, app, qtype))
                val map = HashMap<String, Any?>()
                map["action"] = answer.getString("action")
                map["blocked"] = answer.getBoolean("blocked")
                map["reason"] = answer.getString("reason")
                val rewriteEntry = answer.optJSONObject("rewrite")
                map["rewrite"] = rewriteEntry?.let {
                    hashMapOf(
                        "cname" to it.optString("cname"),
                        "ip4" to it.optString("ip4"),
                        "ip6" to it.optString("ip6"),
                    )
                }
                result.success(map)
            }.onFailure {
                result.error("rule_test_failed", it.message ?: "failed", null)
            }
        }
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/rule_test"
    }
}
