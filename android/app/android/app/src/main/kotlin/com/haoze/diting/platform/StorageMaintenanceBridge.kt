package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.core.rule.RuleIndexLayout
import com.haoze.diting.log.AppDatabase
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class StorageMaintenanceBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/storage"

        private val RULE_TABLES = arrayOf(
            "block_rule",
            "allow_rule",
            "rewrite_rule",
            "subscription",
            "rule_version",
        )
        private val LOG_TABLES = arrayOf(
            "dns_log",
            "dns_race_log",
            "bootstrap_log",
        )
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "closeConnections" -> {
                AppDatabase.closeAll()
                result.success(null)
            }
            "verify" -> result.success(verify(call))
            "clearRuleIndexes" -> {
                for (dataset in RuleDataset.entries) {
                    RuleIndexLayout.deleteAll(
                        RuleIndexLayout.rootDirectory(context.filesDir, dataset),
                    )
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun verify(call: MethodCall): Map<String, Any> {
        val logDatabases = call.argument<List<String>>("logDatabases").orEmpty()
        val ruleDatabases = call.argument<List<String>>("ruleDatabases").orEmpty()
        val errors = ArrayList<String>()
        val logs = LinkedHashMap<String, Any>()
        val rules = LinkedHashMap<String, Any>()

        for (name in logDatabases) {
            val probe = AppDatabase.probe(context.applicationContext, name)
            val ok = probe["probeOk"] == true &&
                "${probe["probeJournalMode"]}".equals("wal", ignoreCase = true) &&
                AppDatabase.writable(context.applicationContext, name)?.let { db ->
                    LOG_TABLES.all { AppDatabase.hasTable(db, it) }
                } == true
            if (!ok) errors.add("log database not ready: $name")
            logs[name] = probe + mapOf("tablesOk" to ok)
        }
        for (name in ruleDatabases) {
            val db = AppDatabase.writable(context.applicationContext, name)
            val ok = db != null && RULE_TABLES.all { AppDatabase.hasTable(db, it) }
            if (!ok) errors.add("rule database not ready: $name")
            rules[name] = mapOf("ok" to ok)
        }
        return mapOf(
            "ok" to errors.isEmpty(),
            "errors" to errors,
            "logs" to logs,
            "rules" to rules,
        )
    }
}
