package com.haoze.diting.automation

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

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
