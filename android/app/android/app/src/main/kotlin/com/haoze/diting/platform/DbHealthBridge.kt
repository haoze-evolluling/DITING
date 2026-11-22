package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.log.AppDatabase
import com.haoze.diting.log.DbWriteHealth
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DbHealthBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/db_health"

        private fun logDatabase(context: Context): String =
            RuleDataset.active(context).logsDatabase()
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(DbWriteHealth.snapshot() + probe())
            else -> result.notImplemented()
        }
    }

    private fun probe(): Map<String, Any> {
        val database = logDatabase(context.applicationContext)
        return runCatching {
            AppDatabase.probe(context.applicationContext, database)
        }.getOrElse { error ->
            mapOf(
                "probeDatabase" to database,
                "probeOk" to false,
                "probeCause" to "${error.javaClass.simpleName}: ${error.message}",
            )
        }
    }
}
