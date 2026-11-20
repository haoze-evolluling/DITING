package com.haoze.diting.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ScheduleBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action: String = intent.action ?: return
        if (action !in HANDLED_ACTIONS) return
        val appContext: Context = context.applicationContext
        runCatching { ScheduleController.reschedule(appContext) }
            .onFailure { Log.w(TAG, "开机/时间变化后重排定时失败", it) }
        runCatching { ScheduleController.install(appContext) }
            .onFailure { Log.w(TAG, "开机/时间变化后安装心跳任务失败", it) }
    }

    companion object {
        private const val TAG = "ScheduleBootReceiver"

        private val HANDLED_ACTIONS: Set<String> = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )
    }
}
