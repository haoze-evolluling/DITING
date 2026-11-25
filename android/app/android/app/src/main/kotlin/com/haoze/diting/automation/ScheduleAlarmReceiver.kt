package com.haoze.diting.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ScheduleAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext: Context = context.applicationContext
        val now: Long = System.currentTimeMillis()
        AutomationContract.prefs(appContext).edit()
            .putLong(AutomationContract.KEY_LAST_TICK_AT_MS, now)
            .apply()
        if (AutomationContract.externalAutomationEnabled(appContext)) {
            runCatching { appContext.sendBroadcast(Intent(AutomationContract.ACTION_SCHEDULE_TICK)) }
                .onFailure { Log.w(TAG, "发送定时到点广播失败", it) }
        }
        val pendingResult: BroadcastReceiver.PendingResult = goAsync()
        Thread({
            try {
                runCatching { AutomationEngine.evaluate(appContext, "schedule") }
                    .onFailure { Log.w(TAG, "求值定时自动化失败", it) }
                runCatching { ScheduleController.syncNext(appContext) }
                    .onFailure { Log.w(TAG, "重排定时任务失败", it) }
            } finally {
                pendingResult.finish()
            }
        }, "diting-schedule-alarm").start()
    }

    companion object {
        private const val TAG = "ScheduleAlarmReceiver"
    }
}
