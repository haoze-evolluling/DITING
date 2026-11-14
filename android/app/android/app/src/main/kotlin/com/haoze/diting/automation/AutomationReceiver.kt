package com.haoze.diting.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import com.haoze.diting.control.DataPlaneControl

/// 签名权限控制入口（A9）：adb / Tasker / 通知动作通过它启动、停止、切换或暂停数据面。
///
/// 这是导出广播接收器，但 manifest 上以 CONTROL 签名权限保护，只有同签名应用能发送。
/// start/stop/toggle 直接改数据面，pause/cancel_pause 只写暂停截止时间并广播新状态；
/// 操作完成后回发一个受 RECEIVE_EVENTS 保护的结果广播，并让 StateBroadcaster 推送状态。
class AutomationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action: String = intent.action ?: return
        if (action !in SUPPORTED_ACTIONS) return
        val appContext: Context = context.applicationContext
        // 数据面操作可能触发前台服务，不能占着主线程做；用 goAsync 保证进程存活到处理完成。
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
            else -> HandleResult(false, "未知动作：$action")
        }
        broadcastResult(context, action, result)
        // 不论成败都推一次最新状态，外部自动化据此更新联动条件。
        StateBroadcaster.broadcast(context)
    }

    /// 把 DataPlaneControl 的结果翻译成 ok/message；NeedsApp 不是失败而是需要用户先打开应用。
    private fun fromDataPlane(result: DataPlaneControl.Result): HandleResult = when (result) {
        DataPlaneControl.Result.Started -> HandleResult(true, "started")
        DataPlaneControl.Result.Stopped -> HandleResult(true, "stopped")
        DataPlaneControl.Result.NeedsApp -> HandleResult(false, "needs_app")
    }

    /// 暂停只记录截止时间：到点后由定时器/上层评估恢复，数据面本身不在这里被反复起停。
    private fun pause(context: Context, intent: Intent): HandleResult {
        val minutes: Int = intent
            .getIntExtra(AutomationContract.EXTRA_PAUSE_MINUTES, AutomationContract.DEFAULT_PAUSE_MINUTES)
            .coerceAtLeast(0)
        val untilMs: Long = System.currentTimeMillis() + minutes.toLong() * 60_000L
        prefs(context).edit().putLong(AutomationContract.KEY_PAUSED_UNTIL_MS, untilMs).apply()
        return HandleResult(true, "paused_until=$untilMs")
    }

    /// 取消暂停：把截止时间清 0，等于立刻恢复。
    private fun cancelPause(context: Context): HandleResult {
        prefs(context).edit().putLong(AutomationContract.KEY_PAUSED_UNTIL_MS, 0L).apply()
        return HandleResult(true, "resumed")
    }

    private fun broadcastResult(context: Context, action: String, result: HandleResult) {
        val intent: Intent = Intent(AutomationContract.ACTION_RESULT)
            .putExtra(AutomationContract.EXTRA_OK, result.ok)
            .putExtra(AutomationContract.EXTRA_MESSAGE, result.message)
            .putExtra(AutomationContract.EXTRA_REQUEST_ACTION, action)
        runCatching { context.sendBroadcast(intent, AutomationContract.PERMISSION_RECEIVE_EVENTS) }
            .onFailure { Log.w(TAG, "发送控制结果广播失败", it) }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)

    /// 单次控制的结果载荷。
    private data class HandleResult(val ok: Boolean, val message: String)

    companion object {
        private const val TAG = "AutomationReceiver"

        private val SUPPORTED_ACTIONS: Set<String> = setOf(
            AutomationContract.ACTION_START,
            AutomationContract.ACTION_STOP,
            AutomationContract.ACTION_TOGGLE,
            AutomationContract.ACTION_PAUSE,
            AutomationContract.ACTION_CANCEL_PAUSE,
        )
    }
}
