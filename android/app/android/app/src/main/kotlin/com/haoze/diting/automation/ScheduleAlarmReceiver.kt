package com.haoze.diting.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log

/// AlarmManager 到点接收器（A7）：仅应用内 alarm 触发，exported=false。
///
/// 触发后记录 last_tick、广播 SCHEDULE_TICK；若仍有未来的 next_due_at，则重排下一次，
/// 让一次性的精确闹钟能自动接续。
class ScheduleAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext: Context = context.applicationContext
        val now: Long = System.currentTimeMillis()
        val prefs: SharedPreferences =
            appContext.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putLong(AutomationContract.KEY_LAST_TICK_AT_MS, now).apply()
        runCatching {
            appContext.sendBroadcast(
                Intent(AutomationContract.ACTION_SCHEDULE_TICK),
                AutomationContract.PERMISSION_RECEIVE_EVENTS,
            )
        }.onFailure { Log.w(TAG, "发送定时到点广播失败", it) }
        // A1：定时到点后求值一次 schedule 触发的自动化规则。
        runCatching { AutomationEngine.evaluate(appContext, "schedule") }
            .onFailure { Log.w(TAG, "求值定时自动化失败", it) }
        val nextDueAtMs: Long = prefs.getLong(AutomationContract.KEY_NEXT_DUE_AT_MS, 0L)
        if (nextDueAtMs > now) ScheduleController.sync(appContext, nextDueAtMs)
    }

    companion object {
        private const val TAG = "ScheduleAlarmReceiver"
    }
}
