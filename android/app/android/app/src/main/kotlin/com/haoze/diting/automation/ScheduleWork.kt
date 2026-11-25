package com.haoze.diting.automation

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

class ScheduleWork(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val context: Context = applicationContext
        val now: Long = System.currentTimeMillis()
        val prefs = AutomationContract.prefs(context)
        val dueAtMs: Long = prefs.getLong(AutomationContract.KEY_NEXT_DUE_AT_MS, 0L)
        prefs.edit().putLong(AutomationContract.KEY_LAST_TICK_AT_MS, now).apply()
        if (AutomationContract.externalAutomationEnabled(context)) {
            runCatching { context.sendBroadcast(Intent(AutomationContract.ACTION_SCHEDULE_TICK)) }
                .onFailure { Log.w(TAG, "发送定时到点广播失败", it) }
        }
        // 到点兜底：精确闹钟被系统丢弃时，由 WorkManager 补一次求值。
        if (dueAtMs > 0L && dueAtMs <= now) {
            runCatching { AutomationEngine.evaluate(context, "schedule") }
                .onFailure { Log.w(TAG, "求值定时自动化失败", it) }
        }
        runCatching { ScheduleController.syncNext(context) }
            .onFailure { Log.w(TAG, "重排定时任务失败", it) }
        return Result.success()
    }

    companion object {
        private const val TAG = "ScheduleWork"
    }
}
