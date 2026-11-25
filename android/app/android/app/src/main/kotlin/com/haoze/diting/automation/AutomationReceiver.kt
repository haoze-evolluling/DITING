package com.haoze.diting.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.haoze.diting.control.DataPlaneControl

/** 外部自动化入口（adb / Tasker 等），受“允许外部自动化控制”开关约束。 */
class AutomationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action: String = intent.action ?: return
        if (action !in SUPPORTED_ACTIONS) return
        val appContext: Context = context.applicationContext
        if (!AutomationContract.externalAutomationEnabled(appContext)) {
            Log.i(TAG, "外部自动化未开启，忽略：$action")
            return
        }
        val pendingResult: BroadcastReceiver.PendingResult = goAsync()
        Thread {
            try {
                handle(appContext, action, intent)
            } catch (error: Throwable) {
                Log.w(TAG, "处理自动化控制失败：$action", error)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun handle(context: Context, action: String, intent: Intent) {
        val result: HandleResult = when (action) {
            AutomationContract.ACTION_START -> fromDataPlane(DataPlaneControl.start(context))
            AutomationContract.ACTION_STOP -> fromDataPlane(DataPlaneControl.stop(context))
            AutomationContract.ACTION_TOGGLE -> fromDataPlane(DataPlaneControl.toggle(context))
            AutomationContract.ACTION_PAUSE -> pause(context, intent)
            AutomationContract.ACTION_CANCEL_PAUSE -> cancelPause(context)
            AutomationContract.ACTION_RUN_RULES -> runRules(context, intent)
            else -> HandleResult(false, "未知动作：$action")
        }
        broadcastResult(context, action, result)
        StateBroadcaster.broadcast(context)
    }

    private fun fromDataPlane(result: DataPlaneControl.Result): HandleResult = when (result) {
        DataPlaneControl.Result.Started -> HandleResult(true, "started")
        DataPlaneControl.Result.Stopped -> HandleResult(true, "stopped")
        DataPlaneControl.Result.NeedsApp -> HandleResult(false, "needs_app")
    }

    private fun pause(context: Context, intent: Intent): HandleResult {
        val minutes: Int = intent
            .getIntExtra(AutomationContract.EXTRA_PAUSE_MINUTES, AutomationContract.DEFAULT_PAUSE_MINUTES)
            .coerceAtLeast(0)
        val untilMs: Long = AutomationPause.pause(context, minutes)
        return HandleResult(true, "paused_until=$untilMs")
    }

    private fun cancelPause(context: Context): HandleResult {
        AutomationPause.resume(context)
        return HandleResult(true, "resumed")
    }

    private fun runRules(context: Context, intent: Intent): HandleResult {
        val eventType: String = intent
            .getStringExtra(AutomationContract.EXTRA_EVENT_TYPE) ?: "manual"
        val applied: List<String> = AutomationEngine.evaluate(context, eventType)
        return HandleResult(true, "rules=${applied.size}")
    }

    private fun broadcastResult(context: Context, action: String, result: HandleResult) {
        if (!AutomationContract.externalAutomationEnabled(context)) return
        val intent: Intent = Intent(AutomationContract.ACTION_RESULT)
            .putExtra(AutomationContract.EXTRA_OK, result.ok)
            .putExtra(AutomationContract.EXTRA_MESSAGE, result.message)
            .putExtra(AutomationContract.EXTRA_REQUEST_ACTION, action)
        runCatching { context.sendBroadcast(intent) }
            .onFailure { Log.w(TAG, "发送控制结果广播失败", it) }
    }

    private data class HandleResult(val ok: Boolean, val message: String)

    companion object {
        private const val TAG = "AutomationReceiver"

        private val SUPPORTED_ACTIONS: Set<String> = setOf(
            AutomationContract.ACTION_START,
            AutomationContract.ACTION_STOP,
            AutomationContract.ACTION_TOGGLE,
            AutomationContract.ACTION_PAUSE,
            AutomationContract.ACTION_CANCEL_PAUSE,
            AutomationContract.ACTION_RUN_RULES,
        )
    }
}
