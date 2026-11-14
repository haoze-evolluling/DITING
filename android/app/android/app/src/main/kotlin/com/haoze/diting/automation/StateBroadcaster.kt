package com.haoze.diting.automation

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import com.haoze.diting.control.DataPlaneControl
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.server.DitingDnsServerService

/// 状态广播器（A5）：把当前数据面状态整理后交给 EventNative 生成冻结 JSON，再以签名权限广播。
///
/// 广播故意不带 setPackage：接收方由 RECEIVE_EVENTS 签名权限限定，同一份事件既能被本应用内的
/// Dart/native 监听者收到，也能被同签名的外部自动化应用（如 Tasker 插件）订阅。
object StateBroadcaster {
    private const val TAG = "StateBroadcaster"

    fun broadcast(context: Context) {
        val appContext: Context = context.applicationContext
        // 状态广播是“尽力而为”的可观测能力，任何异常都不能反噬触发它的控制/刷新流程。
        runCatching { broadcastInternal(appContext) }
            .onFailure { Log.w(TAG, "构建或发送状态广播失败", it) }
    }

    private fun broadcastInternal(context: Context) {
        val workMode: String = DataPlaneControl.workMode(context)
        // 三种数据面各自持有 status()，字段名一致（running/reclaiming/persisted/error/startedAt）。
        val status: Map<String, Any?> = when (workMode) {
            DataPlaneControl.WORK_MODE_DNS -> DitingDnsServerService.status(context)
            DataPlaneControl.WORK_MODE_EXPRESS -> ExpressVpnService.status(context)
            else -> DitingVpnService.status(context)
        }
        val running: Boolean = status["running"] as? Boolean ?: false
        // 服务器模式没有 reclaiming 字段，缺省按未回收处理。
        val reclaiming: Boolean = status["reclaiming"] as? Boolean ?: false
        val persisted: Boolean = status["persisted"] as? Boolean ?: false
        val startedAt: Long = (status["startedAt"] as? Number)?.toLong() ?: 0L
        val error: String? = status["error"] as? String
        val pausedUntil: Long = prefs(context).getLong(AutomationContract.KEY_PAUSED_UNTIL_MS, 0L)

        val json: String = EventNative.buildStateChanged(
            workMode = workMode,
            running = running,
            reclaiming = reclaiming,
            persisted = persisted,
            startedAt = startedAt,
            pausedUntil = pausedUntil,
            error = error,
        )
        val intent: Intent = Intent(AutomationContract.ACTION_STATE_CHANGED)
            .putExtra(AutomationContract.EXTRA_EVENT_JSON, json)
            .putExtra(AutomationContract.EXTRA_SCHEMA, AutomationContract.SCHEMA_VERSION)
        context.sendBroadcast(intent, AutomationContract.PERMISSION_RECEIVE_EVENTS)
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)
}
