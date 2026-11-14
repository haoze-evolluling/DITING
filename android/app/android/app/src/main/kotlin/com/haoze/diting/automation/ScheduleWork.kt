package com.haoze.diting.automation

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/// WorkManager 兜底任务（A7）：闹钟被 Doze/厂商策略吞掉时，由一次性兜底任务或周期心跳补一次 tick。
///
/// 与 ScheduleAlarmReceiver 行为一致：记录 last_tick 并广播 SCHEDULE_TICK；任务自身不做规则求值。
class ScheduleWork(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val context: Context = applicationContext
        val prefs: SharedPreferences =
            context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(AutomationContract.KEY_LAST_TICK_AT_MS, System.currentTimeMillis())
            .apply()
        runCatching {
            context.sendBroadcast(
                Intent(AutomationContract.ACTION_SCHEDULE_TICK),
                AutomationContract.PERMISSION_RECEIVE_EVENTS,
            )
        }.onFailure { Log.w(TAG, "发送定时到点广播失败", it) }
        return Result.success()
    }

    companion object {
        private const val TAG = "ScheduleWork"
    }
}
