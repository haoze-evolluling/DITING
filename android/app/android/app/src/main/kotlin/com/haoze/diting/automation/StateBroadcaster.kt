package com.haoze.diting.automation

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import com.haoze.diting.control.DataPlaneControl
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.root.RootDnsService
import com.haoze.diting.server.ServerDnsService

object StateBroadcaster {
    private const val TAG = "StateBroadcaster"

    fun broadcast(context: Context) {
        val appContext: Context = context.applicationContext
        if (!AutomationContract.externalAutomationEnabled(appContext)) return
        runCatching { broadcastInternal(appContext) }
            .onFailure { Log.w(TAG, "构建或发送状态广播失败", it) }
    }

    private fun broadcastInternal(context: Context) {
        val workMode: String = DataPlaneControl.workMode(context)
        val status: Map<String, Any?> = when {
            workMode == DataPlaneControl.WORK_MODE_SERVER -> ServerDnsService.status()
            DataPlaneControl.usesRootTakeover(context) -> RootDnsService.status(context)
            workMode == DataPlaneControl.WORK_MODE_EXPRESS -> ExpressVpnService.status(context)
            else -> DitingVpnService.status(context)
        }
        val running: Boolean = status["running"] as? Boolean ?: false
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
        context.sendBroadcast(intent)
    }

    private fun prefs(context: Context): SharedPreferences = AutomationContract.prefs(context)
}
