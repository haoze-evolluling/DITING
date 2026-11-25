package com.haoze.diting.platform

import android.content.Context
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.log.AppDatabase
import com.haoze.diting.log.DbWriteHealth
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class DbHealthBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/db_health"

        private fun logDatabase(context: Context): String =
            RuleDataset.active(context).logsDatabase()

        // 打开数据库并读取 PRAGMA 是磁盘操作，放到后台线程执行，
        // 避免启动阶段阻塞 Android 主线程。
        private val workers = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "diting-db-health").apply { isDaemon = true }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> workers.execute {
                ChannelResults.ship(
                    result,
                    runCatching { DbWriteHealth.snapshot() + probe() },
                    "db_health_failed",
                )
            }
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
